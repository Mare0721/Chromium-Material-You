from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

from PySide6.QtCore import QEvent, QObject, QRectF, QUrl
from PySide6.QtGui import (
    QGuiApplication,
    QIcon,
    QPainterPath,
    QRegion,
    QSurfaceFormat,
    QWindow,
)
from PySide6.QtQml import QQmlApplicationEngine

from md3qmlpy.phoenix_backend import PhoenixBackend
from md3qmlpy.stylemanager import StyleManager


def resolve_app_root() -> Path:
    candidates: list[Path] = []

    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.append(exe_dir)

        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            meipass_dir = Path(meipass)
            candidates.append(meipass_dir)
            candidates.append(meipass_dir.parent)

    candidates.append(Path(__file__).resolve().parents[1])

    for root in candidates:
        qml_src = root / "md3qmlcpp" / "material-components-qml-main" / "src"
        if qml_src.exists():
            return root

    return candidates[-1]


class RoundedWindowMaskController(QObject):
    def __init__(self, radius: int = 10) -> None:
        super().__init__()
        self._radius = radius
        self._window: Optional[QWindow] = None

    def attach(self, window: QWindow) -> None:
        self._window = window
        self._window.installEventFilter(self)
        self._apply_mask()

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        if watched is self._window and event.type() in (
            QEvent.Show,
            QEvent.Resize,
            QEvent.WindowStateChange,
        ):
            self._apply_mask()
        return False

    def _apply_mask(self) -> None:
        if self._window is None:
            return

        # Prefer native DWM rounded corners on Windows for smoother anti-aliased edges.
        if self._try_apply_native_rounding():
            return

        if not hasattr(self._window, "setMask"):
            return

        w = int(self._window.width())
        h = int(self._window.height())
        if w <= 0 or h <= 0:
            return
        path = QPainterPath()
        path.addRoundedRect(QRectF(0.0, 0.0, float(w), float(h)), float(self._radius), float(self._radius))
        region = QRegion(path.toFillPolygon().toPolygon())
        self._window.setMask(region)

    def _try_apply_native_rounding(self) -> bool:
        if os.name != "nt" or self._window is None:
            return False
        try:
            import ctypes
            from ctypes import wintypes

            hwnd = int(self._window.winId())
            if hwnd <= 0:
                return False

            DWMWA_WINDOW_CORNER_PREFERENCE = 33
            DWMWCP_ROUND_SMALL = 3

            preference = ctypes.c_int(DWMWCP_ROUND_SMALL)
            result = ctypes.windll.dwmapi.DwmSetWindowAttribute(
                wintypes.HWND(hwnd),
                ctypes.c_uint(DWMWA_WINDOW_CORNER_PREFERENCE),
                ctypes.byref(preference),
                ctypes.sizeof(preference),
            )
            return int(result) == 0
        except Exception:
            return False


def run(qml_root: Optional[Path] = None) -> int:
    os.environ.setdefault("QML_DISABLE_DISK_CACHE", "1")

    format_ = QSurfaceFormat()
    format_.setSamples(4)
    format_.setAlphaBufferSize(8)
    QSurfaceFormat.setDefaultFormat(format_)

    app = QGuiApplication([])

    repo_root = resolve_app_root()
    icon_env = os.environ.get("MD3QMLPY_WINDOW_ICON")
    icon_path: Optional[Path] = None
    if icon_env:
        icon_path = Path(icon_env)
        if not icon_path.is_absolute():
            icon_path = repo_root / icon_path
    else:
        icon_path = (
            repo_root
            / "md3qmlcpp"
            / "material-components-qml-main"
            / "preview"
            / "app_icon.svg"
        )
    if icon_path is not None and icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))
    if qml_root is None:
        qml_root = repo_root / "md3qmlcpp" / "material-components-qml-main" / "src"

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(qml_root))

    style_manager = StyleManager()
    phoenix_backend = PhoenixBackend()

    root_ctx = engine.rootContext()
    root_ctx.setContextProperty(
        "ProjectSourceDir",
        str(repo_root / "md3qmlcpp" / "material-components-qml-main"),
    )
    root_ctx.setContextProperty("StyleManager", style_manager)
    root_ctx.setContextProperty("PhoenixBackend", phoenix_backend)

    app.aboutToQuit.connect(phoenix_backend.shutdown)

    main_qml = qml_root / "App" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(main_qml)))

    if not engine.rootObjects():
        return 1

    rounded_mask = RoundedWindowMaskController(radius=10)
    root_window = engine.rootObjects()[0]
    if isinstance(root_window, QWindow):
        rounded_mask.attach(root_window)
    app._rounded_mask = rounded_mask

    return app.exec()
