from __future__ import annotations

from pipeline.core.checkpoint import CheckpointManager
from pipeline.core.logging import PipelineLogger
from pipeline.models.pipeline_state import PipelineState


class GateManager:
    def __init__(self, checkpoint: CheckpointManager, logger: PipelineLogger) -> None:
        self.checkpoint = checkpoint
        self.logger = logger

    def is_gate_approved(
        self,
        state: PipelineState,
        stage: str,
        approve_gate_arg: str | None,
    ) -> bool:
        del state
        if approve_gate_arg is None:
            return False
        return approve_gate_arg.strip().lower() == stage.strip().lower()

    def wait_gate(
        self,
        state: PipelineState,
        stage: str,
        approve_gate_arg: str | None,
    ) -> bool:
        if self.is_gate_approved(state, stage, approve_gate_arg):
            if state.gate_pending_stage and state.gate_pending_stage.strip().lower() == stage.strip().lower():
                state.gate_pending_stage = None
                self.checkpoint.save(state)
            self.logger.info(f"Gate approved for {stage}")
            return True

        state.gate_pending_stage = stage
        self.checkpoint.save(state)
        self.logger.warn(f"Gate pending for {stage}; rerun with --approve-gate {stage}")
        return False
