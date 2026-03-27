from __future__ import annotations

from pipeline.core.checkpoint import CheckpointManager
from pipeline.core.logging import PipelineLogger
from pipeline.models.config_schema import PipelineConfig
from pipeline.models.pipeline_state import PipelineState


class DecisionHandler:
    def __init__(
        self,
        config: PipelineConfig,
        checkpoint: CheckpointManager,
        logger: PipelineLogger,
    ) -> None:
        self.config = config
        self.checkpoint = checkpoint
        self.logger = logger

    def handle(self, state: PipelineState, decision: str) -> tuple[str, int]:
        normalized = decision.strip().upper()
        proceed_result = ("proceed", state.current_stage + 1)

        if normalized == "PROCEED":
            state.decision_pending = False
            self.checkpoint.save(state)
            return proceed_result

        if normalized == "REFINE":
            if state.refine_count < self.config.thresholds.max_refine:
                state.refine_count += 1
                state.decision_pending = False
                self.checkpoint.save(state)
                return ("refine", 8)
            self.logger.warn("REFINE max reached; proceeding")
            state.decision_pending = False
            self.checkpoint.save(state)
            return proceed_result

        if normalized == "PIVOT":
            if state.pivot_count < self.config.thresholds.max_pivot:
                state.pivot_count += 1
                state.decision_pending = False
                self.checkpoint.save(state)
                return ("pivot", 5)
            self.logger.warn("PIVOT max reached; proceeding")
            state.decision_pending = False
            self.checkpoint.save(state)
            return proceed_result

        self.logger.warn(f"Unknown decision '{decision}'; proceeding")
        state.decision_pending = False
        self.checkpoint.save(state)
        return proceed_result

    def is_decision_pending(self, state: PipelineState) -> bool:
        return state.decision_pending

    def set_pending(self, state: PipelineState) -> None:
        state.decision_pending = True
        self.checkpoint.save(state)
