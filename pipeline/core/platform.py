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
            encoding="utf-8",
            errors="replace",
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
            encoding="utf-8",
            errors="replace",
            check=True,
        )
        return result.stdout.strip() or path
    except (subprocess.SubprocessError, FileNotFoundError):
        return path


def get_repo_dir() -> Path:
    return Path(__file__).parent.parent.parent


def get_orch_path() -> str:
    raw = str(get_repo_dir())
    if is_windows():
        repo = to_posix_path(raw)
        return repo + "/scripts/orchestrate.sh"
    return str(Path(raw) / "scripts" / "orchestrate.sh")


def get_temp_dir() -> Path:
    return Path(tempfile.gettempdir())


def get_bash() -> str:
    if is_windows():
        for candidate in [
            "C:/Program Files/Git/bin/bash.exe",
            "C:/Program Files (x86)/Git/bin/bash.exe",
        ]:
            if Path(candidate).exists():
                return candidate
    if sys.platform == "darwin" and Path("/usr/bin/bash").exists():
        return "/usr/bin/bash"
    if Path("/bin/bash").exists():
        return "/bin/bash"
    return "bash"
