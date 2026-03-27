from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from pipeline.models.config_schema import PipelineConfig
from pipeline.models.stage_result import StageResult


@dataclass
class StageContext:
    topic: str
    slug: str
    state_dir: Path
    paper_dir: Path
    config: PipelineConfig
    logger: Any
    skip_experiment: bool = False


class Stage(ABC):
    @property
    @abstractmethod
    def name(self) -> str:
        """Return the stage identifier."""

    @property
    @abstractmethod
    def description(self) -> str:
        """Return a short human-readable stage description."""

    @abstractmethod
    def run(self, ctx: StageContext) -> StageResult:
        """Execute the stage and return its result."""

    def should_skip(self, ctx: StageContext) -> bool:
        return False
