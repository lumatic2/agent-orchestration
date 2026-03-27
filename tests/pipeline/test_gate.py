from __future__ import annotations

from pipeline.core.checkpoint import CheckpointManager
from pipeline.core.gate import GateManager
from pipeline.models.pipeline_state import PipelineState


def _manager(tmp_path) -> GateManager:
    checkpoint = CheckpointManager(tmp_path / "pipeline.json")
    return GateManager(checkpoint, logger=None)


def test_gate_approved(tmp_path) -> None:
    manager = _manager(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert manager.is_gate_approved(state, "S12", "S12") is True


def test_gate_not_approved(tmp_path) -> None:
    manager = _manager(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert manager.is_gate_approved(state, "S12", None) is False


def test_gate_case_insensitive(tmp_path) -> None:
    manager = _manager(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert manager.is_gate_approved(state, "S12", "s12") is True
