from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


class PipelineLogger:
    def __init__(self, log_dir: Path, json_mode: bool = False) -> None:
        self.log_dir = log_dir
        self.json_mode = json_mode
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def stage_start(self, stage: str, description: str) -> None:
        self._emit("stage_start", stage, f"{description}", description=description)

    def stage_end(self, stage: str, status: str, elapsed: float) -> None:
        self._emit(
            "stage_end",
            stage,
            f"{status} ({elapsed:.2f}s)",
            status=status,
            elapsed=elapsed,
        )

    def agent_call(self, agent: str, task: str, timeout: int) -> None:
        self._emit(
            "agent_call",
            "AGENT",
            f"{agent} timeout={timeout}s task={task}",
            agent=agent,
            task=task,
            timeout=timeout,
        )

    def agent_result(self, agent: str, exit_code: int, elapsed: float, timed_out: bool) -> None:
        self._emit(
            "agent_result",
            "AGENT",
            f"{agent} exit={exit_code} elapsed={elapsed:.2f}s timed_out={timed_out}",
            agent=agent,
            exit_code=exit_code,
            elapsed=elapsed,
            timed_out=timed_out,
        )

    def warn(self, msg: str) -> None:
        self._emit("warn", "WARN", msg)

    def error(self, msg: str) -> None:
        self._emit("error", "ERROR", msg)

    def info(self, msg: str) -> None:
        self._emit("info", "INFO", msg)

    def _json_log_path(self, now: datetime) -> Path:
        return self.log_dir / f"pipeline_{now:%Y-%m-%d}.jsonl"

    def _emit(self, event: str, stage: str, message: str, **extra: Any) -> None:
        now = datetime.now()
        record: dict[str, Any] = {
            "ts": now.isoformat(timespec="seconds"),
            "event": event,
            "stage": stage,
            "message": message,
        }
        if extra:
            record.update(extra)
        if not self.json_mode:
            self._write_human(now, stage, message)
        self._write_json(now, record)

    def _write_human(self, now: datetime, stage: str, message: str) -> None:
        print(f"[{now:%H:%M:%S}] [{stage}] {message}", file=sys.stderr)

    def _write_json(self, now: datetime, record: dict[str, Any]) -> None:
        path = self._json_log_path(now)
        line = json.dumps(record, ensure_ascii=False)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"{line}\n")
