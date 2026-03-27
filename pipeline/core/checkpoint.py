from __future__ import annotations

from datetime import datetime
from pathlib import Path

from pipeline.models.pipeline_state import PipelineState, StageInfo, StageStatus


def timestamp() -> str:
    return datetime.now().isoformat(timespec="seconds")


class CheckpointManager:
    def __init__(self, pipeline_file: Path) -> None:
        self.pipeline_file = pipeline_file

    def load(self) -> PipelineState:
        if self.pipeline_file.exists():
            return PipelineState.from_json(self.pipeline_file)
        return PipelineState(topic="", slug=self.pipeline_file.stem)

    def save(self, state: PipelineState) -> None:
        state.save(self.pipeline_file)

    def stage_start(self, state: PipelineState, stage: str) -> None:
        stage_info = self._get_stage(state, stage)
        now = timestamp()
        stage_info.status = StageStatus.in_progress
        stage_info.start_ts = now
        stage_info.ts = now
        state.current_stage = self._stage_number(stage, state.current_stage)
        self.save(state)

    def stage_complete(self, state: PipelineState, stage: str) -> None:
        stage_info = self._get_stage(state, stage)
        now = timestamp()
        stage_info.status = StageStatus.completed
        stage_info.ts = now
        state.current_stage = self.get_resume_stage(state)
        self.save(state)

    def stage_fail(self, state: PipelineState, stage: str) -> None:
        stage_info = self._get_stage(state, stage)
        stage_info.status = StageStatus.failed
        stage_info.ts = timestamp()
        state.current_stage = self._stage_number(stage, state.current_stage)
        self.save(state)

    def stage_skip(self, state: PipelineState, stage: str) -> None:
        stage_info = self._get_stage(state, stage)
        stage_info.status = StageStatus.skipped
        stage_info.ts = timestamp()
        state.current_stage = self.get_resume_stage(state)
        self.save(state)

    def get_resume_stage(self, state: PipelineState) -> int:
        stage_items = sorted(
            state.stages.items(),
            key=lambda item: self._stage_number(item[0]),
        )
        for stage_name, stage_info in stage_items:
            if stage_info.status != StageStatus.completed:
                return self._stage_number(stage_name)
        return len(stage_items) + 1

    def _get_stage(self, state: PipelineState, stage: str) -> StageInfo:
        if stage not in state.stages:
            state.stages[stage] = StageInfo()
        return state.stages[stage]

    def _stage_number(self, stage: str, default: int = 1) -> int:
        digits = "".join(ch for ch in stage if ch.isdigit())
        if not digits:
            return default
        return int(digits)
