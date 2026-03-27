from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

from pipeline.agents.result_parser import extract_content
from pipeline.core.platform import get_bash, is_windows, to_posix_path

_PROMPT_FILE_THRESHOLD = 2000


@dataclass
class AgentResult:
    content: str
    raw_output: str
    exit_code: int
    agent_name: str
    elapsed_seconds: float
    timed_out: bool = False


class AgentRunner(ABC):
    def __init__(self, orch_path: str) -> None:
        self.orch_path = orch_path

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the stable agent name."""

    def run(self, prompt: str, task_name: str, timeout: int) -> AgentResult:
        start = time.monotonic()
        orch_path = to_posix_path(self.orch_path) if is_windows() else self.orch_path
        env = {**os.environ, "NO_VAULT": "true", "FORCE": "true"}

        tmp_file: Path | None = None
        try:
            if len(prompt) > _PROMPT_FILE_THRESHOLD:
                fd, tmp_path = tempfile.mkstemp(suffix=".md", prefix="prompt_")
                tmp_file = Path(tmp_path)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(
                        "IMPORTANT: This is a RESEARCH task, NOT a code task. "
                        "Ignore any codebase context. Answer the research question directly.\n\n"
                        + prompt
                    )
                file_ref = to_posix_path(str(tmp_file)) if is_windows() else str(tmp_file)
                brief_arg = f"@{file_ref}"
            else:
                brief_arg = prompt

            cmd = [get_bash(), orch_path, self.name, brief_arg, task_name]

            if is_windows():
                # Windows: CREATE_NEW_PROCESS_GROUP for proper tree kill
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    cwd=tempfile.gettempdir(),
                    creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
                )
                try:
                    stdout_b, stderr_b = proc.communicate(timeout=timeout)
                    stdout = stdout_b.decode("utf-8", errors="replace")
                    stderr = stderr_b.decode("utf-8", errors="replace")
                except subprocess.TimeoutExpired:
                    # Kill entire process tree on Windows
                    subprocess.run(
                        ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                        capture_output=True,
                    )
                    proc.wait(timeout=5)
                    elapsed = time.monotonic() - start
                    return AgentResult(
                        content="",
                        raw_output="",
                        exit_code=124,
                        agent_name=self.name,
                        elapsed_seconds=elapsed,
                        timed_out=True,
                    )
                elapsed = time.monotonic() - start
                raw_output = f"{stdout}{stderr}"
                return AgentResult(
                    content=extract_content(raw_output),
                    raw_output=raw_output,
                    exit_code=proc.returncode,
                    agent_name=self.name,
                    elapsed_seconds=elapsed,
                    timed_out=False,
                )
            else:
                # Mac/Linux: process group kill via start_new_session
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    cwd=tempfile.gettempdir(),
                    start_new_session=True,
                )
                try:
                    stdout_b, stderr_b = proc.communicate(timeout=timeout)
                    stdout = stdout_b.decode("utf-8", errors="replace")
                    stderr = stderr_b.decode("utf-8", errors="replace")
                except subprocess.TimeoutExpired:
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                        proc.wait()
                    elapsed = time.monotonic() - start
                    return AgentResult(
                        content="",
                        raw_output="",
                        exit_code=124,
                        agent_name=self.name,
                        elapsed_seconds=elapsed,
                        timed_out=True,
                    )
                elapsed = time.monotonic() - start
                raw_output = f"{stdout}{stderr}"
                return AgentResult(
                    content=extract_content(raw_output),
                    raw_output=raw_output,
                    exit_code=proc.returncode,
                    agent_name=self.name,
                    elapsed_seconds=elapsed,
                    timed_out=False,
                )
        finally:
            if tmp_file and tmp_file.exists():
                tmp_file.unlink(missing_ok=True)
