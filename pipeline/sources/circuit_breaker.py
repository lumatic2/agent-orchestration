from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from pipeline.core.file_ops import atomic_write_json, safe_read


class CircuitBreaker:
    def __init__(
        self,
        state_file: Path,
        max_failures: int = 3,
        cooldown_minutes: int = 30,
    ) -> None:
        self.state_file = state_file
        self.max_failures = max_failures
        self.cooldown_minutes = cooldown_minutes

    def is_open(self, source: str) -> bool:
        data = self._load()
        state = data.get(source, {})
        failures = int(state.get("failures", 0) or 0)
        last_failure_raw = state.get("last_failure")
        if failures < self.max_failures or not last_failure_raw:
            return False
        try:
            last_failure = datetime.fromisoformat(str(last_failure_raw))
        except ValueError:
            return False
        return datetime.utcnow() - last_failure < timedelta(minutes=self.cooldown_minutes)

    def record_success(self, source: str) -> None:
        data = self._load()
        data[source] = {"failures": 0, "last_failure": ""}
        self._save(data)

    def record_failure(self, source: str) -> None:
        data = self._load()
        current = data.get(source, {})
        failures = int(current.get("failures", 0) or 0) + 1
        data[source] = {"failures": failures, "last_failure": datetime.utcnow().isoformat()}
        self._save(data)

    def _load(self) -> dict[str, dict[str, Any]]:
        raw = safe_read(self.state_file, default="{}").strip() or "{}"
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        if not isinstance(data, dict):
            return {}
        return data

    def _save(self, data: dict[str, dict[str, Any]]) -> None:
        atomic_write_json(self.state_file, data)
