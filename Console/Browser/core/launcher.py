import os
import subprocess
import time
import json
from config import CHROME_EXE, WORKERS_DIR
from .profile import ProfileManager, DEFAULT_BROWSER_VERSION

class ChromeLauncher:

    def __init__(
        self,
        worker_id,
        proxy=None,
        compliance_mode=True,
        chrome_exe_path=None,
    ):
        self.worker_id = worker_id
        self.proxy = proxy
        self.compliance_mode = compliance_mode
        self.chrome_exe = chrome_exe_path or CHROME_EXE
        self.process = None
        self.debug_port = 0
        self.user_data_dir = os.path.join(WORKERS_DIR, f"worker_{worker_id}")

    def _prepare_env(self):
        """Prepare UserDataDir and Fingerprint Config"""
        if not os.path.exists(self.user_data_dir):
            os.makedirs(self.user_data_dir)

        fp_path = os.path.join(self.user_data_dir, "fingerprint.json")

        # 指纹只在首次创建时生成，之后重启直接复用，保证同一环境指纹永久不变
        if not os.path.exists(fp_path):
            proxy_ip = self.proxy.get("ip") if self.proxy else None
            fp_data = ProfileManager.generate_fingerprint(
                proxy_ip=proxy_ip,
                browser_version=DEFAULT_BROWSER_VERSION,
                compliance_mode=self.compliance_mode,
            )
            ProfileManager.save_profile(fp_path, fp_data)
            print(f"[Launcher] Worker {self.worker_id}: new fingerprint generated.", flush=True)
        else:
            print(f"[Launcher] Worker {self.worker_id}: reusing existing fingerprint.", flush=True)

        return fp_path

    def launch(self, debug_port=0):
        """Launch Chrome process directly"""
        fp_path = self._prepare_env()

        # Read language from fingerprint
        lang_arg = "--lang=en-US"
        webrtc_prevent_ip_leak = False
        try:
            with open(fp_path, "r", encoding="utf-8") as f:
                fp_data = json.load(f)
                if "language" in fp_data:
                    lang_arg = f"--lang={fp_data['language']}"
                webrtc_prevent_ip_leak = bool(fp_data.get("webrtc", {}).get("prevent_ip_leak", False))
        except: pass

        # Assign a free port
        if debug_port == 0:
            import socket
            sock = socket.socket()
            sock.bind(('', 0))
            self.debug_port = sock.getsockname()[1]
            sock.close()
        else:
            self.debug_port = debug_port

        fp_path = os.path.abspath(fp_path).replace("\\", "/")

        cmd = [
            self.chrome_exe,
            f"--user-data-dir={os.path.join(self.user_data_dir, 'User Data')}",
            f"--fingerprint-config-path={fp_path}",
            f"--remote-debugging-port={self.debug_port}",
            "--remote-allow-origins=*",
            "--no-first-run",
            "--no-default-browser-check",
            lang_arg,
        ]

        # Proxy Handling
        if self.proxy and self.proxy.get("bridge_port"):
            cmd.append(f"--proxy-server=http://127.0.0.1:{self.proxy['bridge_port']}")

        if webrtc_prevent_ip_leak:
            cmd.append("--force-webrtc-ip-handling-policy=disable_non_proxied_udp")

        self.process = subprocess.Popen(
            cmd,
            creationflags=subprocess.CREATE_NO_WINDOW
        )

        # Wait for Chrome to initialize
        time.sleep(2)
        return self.debug_port

    def stop(self):
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except:
                self.process.kill()
