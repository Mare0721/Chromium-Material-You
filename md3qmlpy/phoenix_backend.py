from __future__ import annotations

import asyncio
import importlib
import json
import os
import stat
import shutil
import sys
import threading
import time
from pathlib import Path
from typing import Any, Optional

from PySide6.QtCore import QObject, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication


class PhoenixBackend(QObject):
    """Bridge Phoenix browser runtime into QML while keeping the UI layer intact."""

    profilesChanged = Signal()
    logsChanged = Signal()
    runningIdsChanged = Signal()
    logMessage = Signal(str)

    def __init__(self, parent: Optional[QObject] = None) -> None:
        super().__init__(parent)
        self._lock = threading.RLock()
        self._profiles: list[dict[str, Any]] = []
        self._logs: list[str] = []
        self._launchers: dict[int, Any] = {}
        self._proxies: dict[int, Any] = {}

        self._ready = False
        self._bridge_error = ""
        self._project_root: Optional[Path] = None
        self._profiles_db: Optional[Path] = None
        self._workers_dir: Optional[Path] = None
        self._ChromeLauncher = None
        self._AsyncProxyTunnel = None

        self._loop = asyncio.new_event_loop()
        self._loop_thread = threading.Thread(target=self._loop_runner, daemon=True)
        self._loop_thread.start()

        self._monitor_stop = threading.Event()
        self._monitor_thread = threading.Thread(target=self._process_monitor_runner, daemon=True)
        self._monitor_thread.start()

        self._init_bridge()
        self._load_db()

    def _loop_runner(self) -> None:
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    def _resolve_app_root(self) -> Path:
        if getattr(sys, "frozen", False):
            return Path(sys.executable).resolve().parent
        return Path(__file__).resolve().parents[1]

    def _resolve_browser_dir(self) -> Path:
        candidates: list[Path] = []

        app_root = self._resolve_app_root()
        candidates.append(app_root / "Browser")

        if getattr(sys, "frozen", False):
            exe_dir = Path(sys.executable).resolve().parent
            if (exe_dir / "Browser") not in candidates:
                candidates.append(exe_dir / "Browser")

            meipass = getattr(sys, "_MEIPASS", None)
            if meipass:
                meipass_dir = Path(meipass)
                candidates.append(meipass_dir / "Browser")
                candidates.append(meipass_dir.parent / "Browser")

        for path in candidates:
            if path.exists():
                return path

        return candidates[-1]

    def _ensure_runtime_root(self, app_root: Path) -> Path:
        runtime_root = app_root / "runtime"
        legacy_runtime_root = app_root / "phoenix_runtime"

        if not runtime_root.exists() and legacy_runtime_root.exists():
            try:
                legacy_runtime_root.rename(runtime_root)
                self._append_log("已将 phoenix_runtime 目录迁移为 runtime")
            except Exception as exc:
                self._append_log(f"重命名 runtime 目录失败，尝试复制迁移: {exc}")
                try:
                    shutil.copytree(legacy_runtime_root, runtime_root, dirs_exist_ok=True)
                    shutil.rmtree(legacy_runtime_root, ignore_errors=True)
                    self._append_log("已通过复制方式完成 phoenix_runtime -> runtime 迁移")
                except Exception as copy_exc:
                    self._append_log(f"runtime 目录迁移失败: {copy_exc}")

        runtime_root.mkdir(parents=True, exist_ok=True)
        return runtime_root

    def _process_monitor_runner(self) -> None:
        while not self._monitor_stop.wait(0.8):
            try:
                self._sync_launcher_states()
            except Exception:
                continue

    def _sync_launcher_states(self) -> None:
        stale_ids: list[int] = []
        stale_tunnels: list[tuple[int, Any]] = []

        with self._lock:
            for pid, launcher in list(self._launchers.items()):
                alive = False
                try:
                    alive = bool(launcher.process and launcher.process.poll() is None)
                except Exception:
                    alive = False
                if not alive:
                    stale_ids.append(pid)

            for pid in stale_ids:
                self._launchers.pop(pid, None)
                tunnel = self._proxies.pop(pid, None)
                if tunnel:
                    stale_tunnels.append((pid, tunnel))

        if not stale_ids:
            return

        for _pid, tunnel in stale_tunnels:
            try:
                tunnel.stop()
            except Exception:
                pass

        self._append_log(f"检测到浏览器已退出，状态已同步: {', '.join(str(v) for v in stale_ids)}")
        self.runningIdsChanged.emit()
        self.profilesChanged.emit()

    def _kernel_version_signature(self, browser_source: Path) -> str:
        if not browser_source.exists():
            return "missing"

        manifests = sorted(p.name for p in browser_source.glob("*.manifest"))
        if manifests:
            return f"manifest:{manifests[0]}"

        chrome_exe = browser_source / "chrome.exe"
        if chrome_exe.exists():
            try:
                stat_result = chrome_exe.stat()
                return f"exe:{stat_result.st_size}:{int(stat_result.st_mtime)}"
            except Exception:
                return "exe:unknown"

        return "unknown"

    def _read_kernel_sync_meta(self, meta_path: Path) -> dict[str, Any]:
        try:
            if not meta_path.exists():
                return {}
            with meta_path.open("r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _write_kernel_sync_meta(self, meta_path: Path, source_version: str, runtime_version: str) -> None:
        payload = {
            "source_version": source_version,
            "runtime_version": runtime_version,
            "synced_at": int(time.time()),
        }
        try:
            with meta_path.open("w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)
        except Exception as exc:
            self._append_log(f"写入内核版本校验信息失败: {exc}")

    def _is_reparse_point(self, path: Path) -> bool:
        try:
            if not path.exists():
                return False
            if path.is_symlink():
                return True
            file_attrs = getattr(os.lstat(path), "st_file_attributes", 0)
            reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)
            return bool(file_attrs & reparse_flag)
        except Exception:
            return False

    def _remove_reparse_dir(self, path: Path) -> None:
        try:
            os.rmdir(path)
        except Exception as exc:
            raise RuntimeError(f"移除链接目录失败: {path} ({exc})") from exc

    def _ensure_physical_runtime_chrome_exe(self, runtime_root: Path, legacy_project_root: Path) -> Path:
        runtime_browser_source = runtime_root / "browser_source"
        runtime_chrome_exe = runtime_browser_source / "chrome.exe"
        legacy_browser_source = legacy_project_root / "browser_source"
        legacy_chrome_exe = legacy_browser_source / "chrome.exe"
        meta_path = runtime_root / ".kernel_sync_meta.json"

        force_copy_kernel = str(os.environ.get("CONSOLE_COPY_KERNEL", "")).strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )
        lightweight_kernel_mode = getattr(sys, "frozen", False) and not force_copy_kernel

        # In packaged mode, reuse built-in kernel directly to avoid duplicating ~500MB browser_source in runtime.
        if lightweight_kernel_mode and legacy_chrome_exe.exists():
            if runtime_browser_source.exists():
                try:
                    if self._is_reparse_point(runtime_browser_source):
                        self._remove_reparse_dir(runtime_browser_source)
                    else:
                        shutil.rmtree(runtime_browser_source, ignore_errors=True)
                    self._append_log("已启用轻量内核模式：复用内置 browser_source，并释放 runtime/browser_source")
                except Exception as exc:
                    self._append_log(f"清理 runtime/browser_source 失败: {exc}")
            return legacy_chrome_exe

        if runtime_browser_source.exists() and self._is_reparse_point(runtime_browser_source):
            self._append_log("检测到 browser_source 为链接目录，正在切换为物理独立目录...")
            self._remove_reparse_dir(runtime_browser_source)

        if not legacy_chrome_exe.exists():
            return runtime_chrome_exe

        source_version = self._kernel_version_signature(legacy_browser_source)
        runtime_version = self._kernel_version_signature(runtime_browser_source)
        sync_meta = self._read_kernel_sync_meta(meta_path)
        synced_source_version = str(sync_meta.get("source_version", ""))

        needs_sync = (
            (not runtime_chrome_exe.exists())
            or synced_source_version != source_version
            or runtime_version != source_version
        )

        if not needs_sync:
            return runtime_chrome_exe

        runtime_browser_source.mkdir(parents=True, exist_ok=True)
        if runtime_chrome_exe.exists():
            self._append_log(
                f"检测到浏览器内核版本变化，正在同步到本地目录 ({runtime_version} -> {source_version})..."
            )
        else:
            self._append_log("正在复制浏览器内核到 runtime/browser_source（首次可能较慢）...")

        started = time.time()
        shutil.copytree(legacy_browser_source, runtime_browser_source, dirs_exist_ok=True)
        elapsed = time.time() - started

        runtime_version_after = self._kernel_version_signature(runtime_browser_source)
        self._write_kernel_sync_meta(meta_path, source_version, runtime_version_after)
        self._append_log(f"浏览器内核物理同步完成，用时 {elapsed:.1f}s，版本 {runtime_version_after}")

        return runtime_chrome_exe

    def _ensure_physical_runtime_drivers_dir(self, runtime_root: Path, legacy_project_root: Path) -> Path:
        runtime_drivers_dir = runtime_root / "drivers"
        legacy_drivers_dir = legacy_project_root / "drivers"

        force_copy_drivers = str(os.environ.get("CONSOLE_COPY_DRIVERS", "")).strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )

        if runtime_drivers_dir.exists() and self._is_reparse_point(runtime_drivers_dir):
            self._append_log("检测到 drivers 为链接目录，正在切换为物理独立目录...")
            self._remove_reparse_dir(runtime_drivers_dir)

        if getattr(sys, "frozen", False) and not force_copy_drivers:
            if runtime_drivers_dir.exists():
                try:
                    is_empty = not any(runtime_drivers_dir.iterdir())
                except Exception:
                    is_empty = False
                if is_empty:
                    try:
                        runtime_drivers_dir.rmdir()
                    except Exception:
                        pass
            if legacy_drivers_dir.exists():
                return legacy_drivers_dir
            return runtime_drivers_dir

        runtime_drivers_dir.mkdir(parents=True, exist_ok=True)

        has_local_drivers = False
        try:
            has_local_drivers = any(runtime_drivers_dir.iterdir())
        except Exception:
            has_local_drivers = False

        if not has_local_drivers and legacy_drivers_dir.exists():
            self._append_log("正在复制驱动文件到 runtime/drivers...")
            started = time.time()
            shutil.copytree(legacy_drivers_dir, runtime_drivers_dir, dirs_exist_ok=True)
            elapsed = time.time() - started
            self._append_log(f"驱动文件物理复制完成，用时 {elapsed:.1f}s")

        return runtime_drivers_dir

    def _init_bridge(self) -> None:
        try:
            browser_dir = self._resolve_browser_dir()
            if not browser_dir.exists():
                self._bridge_error = f"未找到 Browser 目录: {browser_dir}"
                self._append_log(self._bridge_error)
                return

            browser_path = str(browser_dir)
            if browser_path not in sys.path:
                sys.path.insert(0, browser_path)

            browser_config = importlib.import_module("config")
            launcher_module = importlib.import_module("core.launcher")
            proxy_module = importlib.import_module("network.proxy_tunnel")

            legacy_project_root = Path(getattr(browser_config, "PROJECT_ROOT", browser_dir))
            app_root = self._resolve_app_root()

            runtime_root = self._ensure_runtime_root(app_root)

            runtime_workers_dir = runtime_root / "workers"
            runtime_workers_dir.mkdir(parents=True, exist_ok=True)

            runtime_drivers_dir = self._ensure_physical_runtime_drivers_dir(runtime_root, legacy_project_root)
            runtime_chrome_exe = self._ensure_physical_runtime_chrome_exe(runtime_root, legacy_project_root)

            browser_config.PROJECT_ROOT = str(runtime_root)
            browser_config.WORKERS_DIR = str(runtime_workers_dir)
            browser_config.DRIVERS_DIR = str(runtime_drivers_dir)
            browser_config.CHROME_EXE = str(runtime_chrome_exe)

            launcher_module.WORKERS_DIR = str(runtime_workers_dir)
            launcher_module.CHROME_EXE = str(runtime_chrome_exe)

            ChromeLauncher = launcher_module.ChromeLauncher
            AsyncProxyTunnel = proxy_module.AsyncProxyTunnel

            self._project_root = runtime_root
            self._profiles_db = self._project_root / "profiles.json"
            self._workers_dir = self._project_root / "workers"
            self._workers_dir.mkdir(parents=True, exist_ok=True)

            self._ChromeLauncher = ChromeLauncher
            self._AsyncProxyTunnel = AsyncProxyTunnel
            self._ready = True
            self._append_log(f"Phoenix 程序目录: {app_root}")
            self._append_log(f"Phoenix 运行目录: {self._project_root}")
            self._append_log(f"浏览器环境目录: {runtime_workers_dir}")
            self._append_log(f"浏览器内核路径: {runtime_chrome_exe}")
            if not runtime_chrome_exe.exists():
                self._append_log("警告：未找到 chrome.exe，请将内核文件放入 runtime/browser_source")
            self._append_log("Phoenix 后端桥接已就绪")
        except Exception as exc:
            self._bridge_error = str(exc)
            self._append_log(f"Phoenix 后端桥接初始化失败: {exc}")

    def _append_log(self, message: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        line = f"[{stamp}] {message}"
        with self._lock:
            self._logs.append(line)
            if len(self._logs) > 2000:
                self._logs = self._logs[-2000:]
        self.logMessage.emit(line)
        self.logsChanged.emit()

    def _save_db(self) -> None:
        if not self._profiles_db:
            return
        self._profiles_db.parent.mkdir(parents=True, exist_ok=True)
        with self._profiles_db.open("w", encoding="utf-8") as f:
            json.dump(self._profiles, f, indent=2, ensure_ascii=False)

    def _load_db(self) -> None:
        if not self._profiles_db:
            self._profiles = []
            self.profilesChanged.emit()
            return

        try:
            if self._profiles_db.exists():
                with self._profiles_db.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        self._profiles = data
                    else:
                        self._profiles = []
            else:
                self._profiles = []
        except Exception as exc:
            self._profiles = []
            self._append_log(f"加载环境数据失败: {exc}")

        self.profilesChanged.emit()

    def _parse_proxy(self, value: str) -> Optional[dict[str, Any]]:
        try:
            text = value.strip()
            if not text:
                return None
            scheme = "socks5"
            if "://" in text:
                scheme, text = text.split("://", 1)

            parts = text.split(":")
            if len(parts) == 4:
                return {
                    "scheme": scheme,
                    "ip": parts[0],
                    "port": int(parts[1]),
                    "user": parts[2],
                    "pass": parts[3],
                }
            if len(parts) == 2:
                return {
                    "scheme": scheme,
                    "ip": parts[0],
                    "port": int(parts[1]),
                    "user": "",
                    "pass": "",
                }
        except Exception:
            return None
        return None

    def _normalize_ids(self, ids: Any) -> list[int]:
        out: list[int] = []
        if ids is None:
            return out

        # QML 传入的 QVariantList 可能本身就是 list，也可能是其他包装类型
        if not isinstance(ids, (list, tuple, set)):
            ids = [ids]

        for raw in ids:
            try:
                # 尝试多种方式提取 int
                if isinstance(raw, (int, float)):
                    val = int(raw)
                elif hasattr(raw, 'toInt'):
                    val = raw.toInt()
                elif hasattr(raw, 'toVariant'):
                    val = int(raw.toVariant())
                else:
                    val = int(raw)
                if val >= 0:
                    out.append(val)
            except Exception:
                continue
        return sorted(set(out))

    def _find_profile(self, pid: int) -> Optional[dict[str, Any]]:
        for profile in self._profiles:
            if int(profile.get("id", -1)) == pid:
                return profile
        return None

    def _is_running(self, pid: int) -> bool:
        launcher = self._launchers.get(pid)
        if not launcher:
            return False
        try:
            return launcher.process and launcher.process.poll() is None
        except Exception:
            return False

    @Property(bool, notify=profilesChanged)
    def ready(self) -> bool:
        return self._ready

    @Property(str, notify=logsChanged)
    def bridgeError(self) -> str:
        return self._bridge_error

    @Property("QVariantList", notify=profilesChanged)
    def profiles(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(p) for p in self._profiles]

    @Property("QVariantList", notify=profilesChanged)
    def profileIds(self) -> list[int]:
        with self._lock:
            return [int(p.get("id", -1)) for p in self._profiles if int(p.get("id", -1)) >= 0]

    @Property("QVariantList", notify=runningIdsChanged)
    def runningIds(self) -> list[int]:
        with self._lock:
            return [pid for pid in self._launchers if self._is_running(pid)]

    @Property(int, notify=profilesChanged)
    def profileCount(self) -> int:
        with self._lock:
            return len(self._profiles)

    @Property(int, notify=runningIdsChanged)
    def runningCount(self) -> int:
        return len(self.runningIds)

    @Property(str, notify=logsChanged)
    def logsText(self) -> str:
        with self._lock:
            return "\n".join(self._logs)

    @Slot(result="QVariantList")
    def getProfiles(self) -> list[dict[str, Any]]:
        return self.profiles

    @Slot(int, result=int)
    def profileIdAt(self, index: int) -> int:
        idx = int(index)
        with self._lock:
            if idx < 0 or idx >= len(self._profiles):
                return -1
            return int(self._profiles[idx].get("id", -1))

    def _proxy_to_text(self, proxy: Any, mask_password: bool = True) -> str:
        if not proxy or not isinstance(proxy, dict):
            return ""

        scheme = str(proxy.get("scheme") or "socks5")
        ip = str(proxy.get("ip") or "")
        port = str(proxy.get("port") or "")
        user = str(proxy.get("user") or "")
        password = str(proxy.get("pass") or "")

        if user:
            secret = "***" if mask_password else password
            return f"{scheme}://{ip}:{port}:{user}:{secret}"
        return f"{scheme}://{ip}:{port}"

    @Slot(int, result=str)
    def profileProxyText(self, pid: int) -> str:
        with self._lock:
            profile = self._find_profile(int(pid))

        if not profile:
            return "未设置"

        proxy = profile.get("proxy")
        if not proxy:
            return "未设置"

        text = self._proxy_to_text(proxy, mask_password=True)
        return text if text else "未设置"

    @Slot(int, result=str)
    def profileProxyRawText(self, pid: int) -> str:
        with self._lock:
            profile = self._find_profile(int(pid))

        if not profile:
            return ""

        return self._proxy_to_text(profile.get("proxy"), mask_password=False)

    @Slot(str, int, result=int)
    def importProxies(self, proxy_text: str, quantity: int = 0) -> int:
        lines = [line.strip() for line in proxy_text.splitlines() if line.strip()]
        count = int(quantity) if int(quantity) > 0 else len(lines)
        if count <= 0:
            self._append_log("导入已跳过：代理列表为空")
            return 0

        with self._lock:
            current_max = max((int(p.get("id", 0)) for p in self._profiles), default=0)
            new_profiles: list[dict[str, Any]] = []
            for idx in range(count):
                proxy = self._parse_proxy(lines[idx % len(lines)]) if lines else None
                pid = current_max + idx + 1
                new_profiles.append({
                    "id": pid,
                    "proxy": proxy,
                    "created": time.time(),
                })
            self._profiles.extend(new_profiles)
            try:
                self._save_db()
            except Exception as exc:
                self._append_log(f"保存环境数据失败: {exc}")
                return 0

        self._append_log(f"已导入 {count} 个环境")
        self.profilesChanged.emit()
        return count

    @Slot("QVariantList", str, result=int)
    def setProfilesProxy(self, ids: Any, proxy_text: str) -> int:
        targets = self._normalize_ids(ids)
        if not targets:
            self._append_log("修改代理已跳过：未提供有效环境 ID")
            return 0

        raw_text = str(proxy_text or "").strip()
        new_proxy: Optional[dict[str, Any]] = None

        if raw_text:
            parsed = self._parse_proxy(raw_text)
            if not parsed:
                self._append_log("修改代理失败：格式无效，示例 socks5://127.0.0.1:1080:user:pass")
                return 0
            new_proxy = parsed

        updated = 0
        skipped: list[int] = []

        with self._lock:
            for pid in targets:
                profile = self._find_profile(pid)
                if not profile:
                    skipped.append(pid)
                    continue
                profile["proxy"] = dict(new_proxy) if isinstance(new_proxy, dict) else None
                updated += 1

            if updated:
                try:
                    self._save_db()
                except Exception as exc:
                    self._append_log(f"保存代理修改失败: {exc}")
                    return 0

        if updated:
            if new_proxy:
                self._append_log(f"已更新 {updated} 个环境代理")
            else:
                self._append_log(f"已清空 {updated} 个环境代理")
            self.profilesChanged.emit()

        if skipped:
            self._append_log(f"以下环境不存在，已跳过: {', '.join(map(str, skipped))}")

        return updated

    def _start_worker(self, pid: int) -> None:
        if not self._ready or not self._ChromeLauncher:
            self._append_log(f"[{pid}] 启动已跳过：后端未就绪")
            return

        with self._lock:
            if self._is_running(pid):
                return
            profile = self._find_profile(pid)

        if not profile:
            self._append_log(f"[{pid}] 启动已跳过：环境不存在")
            return

        proxy_cfg = profile.get("proxy")

        def launch_browser(bridge_port: int = 0) -> None:
            try:
                launch_proxy = {"bridge_port": bridge_port} if bridge_port else None
                launcher = self._ChromeLauncher(pid, launch_proxy)
                cdp_port = launcher.launch()
                with self._lock:
                    self._launchers[pid] = launcher
                self._append_log(f"[{pid}] 启动成功 (CDP {cdp_port})")
                self.runningIdsChanged.emit()
                self.profilesChanged.emit()
            except Exception as exc:
                self._append_log(f"[{pid}] 启动失败: {exc}")

        if proxy_cfg and self._AsyncProxyTunnel:
            tunnel = self._AsyncProxyTunnel(proxy_cfg)
            future = asyncio.run_coroutine_threadsafe(tunnel.start(), self._loop)

            def tunnel_ready(done_future: Any) -> None:
                try:
                    local_port = int(done_future.result())
                    with self._lock:
                        self._proxies[pid] = tunnel
                    self._append_log(f"[{pid}] 代理隧道就绪 127.0.0.1:{local_port}")
                    launch_browser(local_port)
                except Exception as exc:
                    self._append_log(f"[{pid}] 代理隧道失败: {exc}")

            future.add_done_callback(tunnel_ready)
            return

        launch_browser(0)

    @Slot("QVariantList")
    def startProfiles(self, ids: Any) -> None:
        explicit_request = ids is not None
        targets = self._normalize_ids(ids)

        if explicit_request and not targets:
            self._append_log("启动已跳过：未提供有效环境 ID")
            return

        if not explicit_request:
            with self._lock:
                targets = [int(p.get("id", -1)) for p in self._profiles if "id" in p]

        for pid in targets:
            threading.Thread(target=self._start_worker, args=(pid,), daemon=True).start()

    @Slot(int)
    def startSingleProfile(self, pid: int) -> None:
        """Start a single profile by integer ID - avoids QVariantList conversion issues."""
        pid = int(pid)
        if pid < 0:
            self._append_log("启动已跳过：无效环境 ID")
            return
        threading.Thread(target=self._start_worker, args=(pid,), daemon=True).start()

    @Slot(int)
    def stopSingleProfile(self, pid: int) -> None:
        """Stop a single profile by integer ID."""
        pid = int(pid)
        if pid < 0:
            return
        self.stopProfiles([pid])

    @Slot("QVariantList")
    def stopProfiles(self, ids: Any) -> None:
        explicit_request = ids is not None
        targets = self._normalize_ids(ids)

        if explicit_request and not targets:
            self._append_log("停止已跳过：未提供有效环境 ID")
            return

        if not explicit_request:
            with self._lock:
                targets = list(self._launchers.keys())

        stopped = 0
        with self._lock:
            for pid in targets:
                launcher = self._launchers.pop(pid, None)
                if launcher:
                    try:
                        launcher.stop()
                        stopped += 1
                    except Exception:
                        pass

                tunnel = self._proxies.pop(pid, None)
                if tunnel:
                    try:
                        tunnel.stop()
                    except Exception:
                        pass

        if stopped:
            self._append_log(f"已停止 {stopped} 个浏览器")
        self.runningIdsChanged.emit()
        self.profilesChanged.emit()

    @Slot("QVariantList", result=int)
    def deleteProfiles(self, ids: Any) -> int:
        targets = self._normalize_ids(ids)
        if not targets:
            return 0

        deleted: list[int] = []
        skipped: list[int] = []

        with self._lock:
            for pid in targets:
                if self._is_running(pid):
                    skipped.append(pid)
                    continue
                if self._find_profile(pid):
                    deleted.append(pid)

            if deleted:
                self._profiles = [p for p in self._profiles if int(p.get("id", -1)) not in deleted]
                self._save_db()

        for pid in deleted:
            self._delete_worker_dir_async(pid)

        if deleted:
            self._append_log(f"已删除 {len(deleted)} 个环境")
        if skipped:
            self._append_log(f"已跳过运行中的环境: {', '.join(map(str, skipped))}")

        self.profilesChanged.emit()
        return len(deleted)

    @Slot()
    def startAll(self) -> None:
        self.startProfiles(None)

    @Slot()
    def stopAll(self) -> None:
        self.stopProfiles(None)

    @Slot(result=int)
    def deleteStopped(self) -> int:
        with self._lock:
            candidates = [
                int(p.get("id", -1))
                for p in self._profiles
                if int(p.get("id", -1)) >= 0 and not self._is_running(int(p.get("id", -1)))
            ]
        return self.deleteProfiles(candidates)

    def _set_clipboard_text(self, text: str) -> bool:
        try:
            app = QGuiApplication.instance()
            if not app:
                return False
            cb = app.clipboard()
            if not cb:
                return False
            cb.setText(text)
            return True
        except Exception:
            return False

    @Slot("QVariantList", result=str)
    def copyIdsToClipboard(self, ids: Any) -> str:
        targets = self._normalize_ids(ids)
        if not targets:
            return ""
        text = "\n".join(str(v) for v in targets)
        if self._set_clipboard_text(text):
            self._append_log(f"已复制 {len(targets)} 个环境 ID")
        return text

    @Slot("QVariantList", result=str)
    def copyProxiesToClipboard(self, ids: Any) -> str:
        targets = self._normalize_ids(ids)
        if not targets:
            return ""

        lines: list[str] = []
        missing_proxy: list[int] = []

        with self._lock:
            for pid in targets:
                profile = self._find_profile(pid)
                if not profile:
                    missing_proxy.append(pid)
                    continue

                proxy_text = self._proxy_to_text(profile.get("proxy"), mask_password=False)
                if proxy_text:
                    lines.append(proxy_text)
                else:
                    missing_proxy.append(pid)

        if not lines:
            self._append_log("复制代理已跳过：选中环境没有可复制代理")
            return ""

        text = "\n".join(lines)
        if self._set_clipboard_text(text):
            self._append_log(f"已复制 {len(lines)} 条代理")
            if missing_proxy:
                self._append_log(f"以下环境未配置代理，已跳过: {', '.join(map(str, missing_proxy))}")

        return text

    def _delete_worker_dir_async(self, pid: int) -> None:
        if not self._workers_dir:
            return

        worker_path = self._workers_dir / f"worker_{pid}"

        def _cleanup() -> None:
            if not worker_path.exists():
                return
            try:
                shutil.rmtree(worker_path, ignore_errors=True)
            except Exception:
                pass

        threading.Thread(target=_cleanup, daemon=True).start()

    @Slot(result="QVariantList")
    def getRunningIds(self) -> list[int]:
        return self.runningIds

    @Slot()
    def reloadProfiles(self) -> None:
        self._load_db()
        self._append_log("环境数据已刷新")

    @Slot()
    def clearLogs(self) -> None:
        with self._lock:
            self._logs.clear()
        self.logsChanged.emit()

    @Slot()
    def shutdown(self) -> None:
        self._monitor_stop.set()
        if self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=1.2)

        try:
            self.stopProfiles(None)
        except Exception:
            pass

        if self._loop.is_running():
            self._loop.call_soon_threadsafe(self._loop.stop)
        self._append_log("Phoenix 后端已停止")
