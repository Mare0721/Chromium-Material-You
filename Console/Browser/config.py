import os

# Phoenix Project Root: e:\src\Browser\Phoenix
PHOENIX_DIR = os.path.dirname(os.path.abspath(__file__))

# Project Root: e:\src\Browser
PROJECT_ROOT = PHOENIX_DIR

# Paths
# chrome.exe is in e:\src\Browser\browser_source\chrome.exe
CHROME_EXE = os.path.join(PROJECT_ROOT, "browser_source", "chrome.exe")
WORKERS_DIR = os.path.join(PROJECT_ROOT, "workers")
DRIVERS_DIR = os.path.join(PROJECT_ROOT, "drivers")

# Data
DEFAULT_DEBUG_PORT = 9222
