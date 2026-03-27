from __future__ import annotations

from datetime import datetime

from pipeline.core.logging import PipelineLogger
from pipeline.models.config_schema import PipelineConfig
from pipeline.models.pipeline_state import PipelineState, StageStatus


class WatchdogChecker:
    def __init__(self, config: PipelineConfig, logger: PipelineLogger) -> None:
        self.config = config
        self.logger = logger

    def check(self, state: PipelineState, skip_stage: str | None = None) -> list[str]:
        stale: list[str] = []
        now = datetime.now()
        stale_minutes = self.config.timeouts.watchdog_stale_minutes

        for stage_name, stage_info in state.stages.items():
            if stage_info.status != StageStatus.in_progress:
                continue
            if skip_stage and stage_name == skip_stage:
                continue
            if not stage_info.start_ts:
                continue

            try:
                started = datetime.fromisoformat(stage_info.start_ts)
            except ValueError:
                self.logger.warn(f"Invalid start_ts for {stage_name}: {stage_info.start_ts}")
                continue

            age_minutes = (now - started).total_seconds() / 60.0
            if age_minutes > stale_minutes:
                stale.append(stage_name)

        return stale
