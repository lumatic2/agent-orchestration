from __future__ import annotations

from dataclasses import dataclass


@dataclass
class StageResult:
    content: str
    gate_required: bool = False
    decision_required: bool = False
    decision_type: str | None = None
    exit_code: int = 0
