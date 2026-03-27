from __future__ import annotations

import os
import subprocess
import time

from pipeline.agents.base import AgentResult, AgentRunner
from pipeline.agents.result_parser import extract_content
from pipeline.core.platform import is_windows, to_posix_path, get_bash


class ClaudeRunner(AgentRunner):
    def __init__(self, orch_path: str) -> None:
        self.orch_path = orch_path

    @property
    def name(self) -> str:
        return "claude"

    def run(self, prompt: str, task_name: str, timeout: int) -> AgentResult:
        start = time.monotonic()
        orch_path = to_posix_path(self.orch_path) if is_windows() else self.orch_path
        cmd = [get_bash(), orch_path, self.name, prompt, task_name]
        env = {**os.environ, "NO_VAULT": "true", "FORCE": "true"}
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                encoding="utf-8", errors="replace",
                timeout=timeout,
                env=env,
            )
        except subprocess.TimeoutExpired as exc:
            elapsed = time.monotonic() - start
            raw_output = f"{exc.stdout or ''}{exc.stderr or ''}"
            return AgentResult(
                content="",
                raw_output=raw_output,
                exit_code=124,
                agent_name=self.name,
                elapsed_seconds=elapsed,
                timed_out=True,
            )

        elapsed = time.monotonic() - start
        raw_output = f"{proc.stdout}{proc.stderr}"
        return AgentResult(
            content=extract_content(raw_output),
            raw_output=raw_output,
            exit_code=proc.returncode,
            agent_name=self.name,
            elapsed_seconds=elapsed,
            timed_out=False,
        )
