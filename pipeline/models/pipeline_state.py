from __future__ import annotations

import json
from enum import Enum
from pathlib import Path

from pydantic import BaseModel, Field

from pipeline.core.file_ops import atomic_write


class StageStatus(str, Enum):
    pending = "pending"
    in_progress = "in_progress"
    completed = "completed"
    skipped = "skipped"
    failed = "failed"


class StageInfo(BaseModel):
    status: StageStatus = Field(default=StageStatus.pending)
    ts: str = Field(default="")
    start_ts: str | None = Field(default=None)


def _default_stages() -> dict[str, StageInfo]:
    return {f"S{i:02d}": StageInfo() for i in range(1, 17)}


class PipelineState(BaseModel):
    topic: str
    slug: str
    current_stage: int = Field(default=1)
    skip_experiment: bool = Field(default=False)
    gate_pending_stage: str | None = Field(default=None)
    decision_pending: bool = Field(default=False)
    refine_count: int = Field(default=0)
    pivot_count: int = Field(default=0)
    stages: dict[str, StageInfo] = Field(default_factory=_default_stages)

    @classmethod
    def from_json(cls, path: Path) -> PipelineState:
        data = json.loads(path.read_text(encoding="utf-8"))
        return cls.model_validate(data)

    def save(self, path: Path) -> None:
        content = self.model_dump_json(indent=2)
        atomic_write(path, content)
