from __future__ import annotations

import platform
import subprocess
import sys
import tempfile
from pathlib import Path


def is_windows() -> bool:
    if sys.platform == "win32":
        return True
    info = f"{platform.uname().system} {platform.uname().release}".upper()
    return any(marker in info for marker in ("MINGW", "MSYS", "CYGWIN"))


def to_native_path(path: str) -> str:
    if not is_windows():
        return path
    try:
        result = subprocess.run(
            ["cygpath", "-m", path],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip() or path
    except (subprocess.SubprocessError, FileNotFoundError):
        return path


def to_posix_path(path: str) -> str:
    if not is_windows():
        return path
    try:
        result = subprocess.run(
            ["cygpath", "-u", path],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip() or path
    except (subprocess.SubprocessError, FileNotFoundError):
        return path


def get_temp_dir() -> Path:
    return Path(tempfile.gettempdir())


def get_shell() -> str:
    if sys.platform == "darwin" and Path("/usr/bin/bash").exists():
        return "/usr/bin/bash"
    if Path("/bin/bash").exists():
        return "/bin/bash"
    return "bash"
