from __future__ import annotations

from pipeline.core.checkpoint import CheckpointManager
from pipeline.core.decision import DecisionHandler
from pipeline.models.config_schema import PipelineConfig
from pipeline.models.pipeline_state import PipelineState


class _Logger:
    def info(self, _message: str) -> None:
        return None

    def warn(self, _message: str) -> None:
        return None


def _handler(tmp_path) -> DecisionHandler:
    config = PipelineConfig()
    checkpoint = CheckpointManager(tmp_path / "pipeline.json")
    return DecisionHandler(config, checkpoint, _Logger())


def test_proceed(tmp_path) -> None:
    handler = _handler(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert handler.handle(state, "PROCEED") == ("proceed", state.current_stage + 1)


def test_refine(tmp_path) -> None:
    handler = _handler(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert handler.handle(state, "REFINE") == ("refine", 8)
    assert state.refine_count == 1


def test_pivot(tmp_path) -> None:
    handler = _handler(tmp_path)
    state = PipelineState(topic="test", slug="test")
    assert handler.handle(state, "PIVOT") == ("pivot", 5)
    assert state.pivot_count == 1


def test_refine_max(tmp_path) -> None:
    handler = _handler(tmp_path)
    state = PipelineState(topic="test", slug="test", current_stage=4, refine_count=3)
    assert handler.handle(state, "REFINE") == ("proceed", 5)
