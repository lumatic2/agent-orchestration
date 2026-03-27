from __future__ import annotations

from pipeline.core.checkpoint import CheckpointManager
from pipeline.models.pipeline_state import PipelineState, StageStatus


def test_load_new(tmp_path) -> None:
    manager = CheckpointManager(tmp_path / "pipeline.json")
    state = manager.load()
    assert isinstance(state, PipelineState)
    assert state.slug == "pipeline"


def test_save_and_load(tmp_path) -> None:
    path = tmp_path / "pipeline.json"
    manager = CheckpointManager(path)
    state = PipelineState(topic="test", slug="test", current_stage=7)
    state.refine_count = 2
    manager.save(state)

    loaded = manager.load()
    assert loaded.topic == "test"
    assert loaded.slug == "test"
    assert loaded.current_stage == 7
    assert loaded.refine_count == 2


def test_stage_start(tmp_path) -> None:
    manager = CheckpointManager(tmp_path / "pipeline.json")
    state = PipelineState(topic="test", slug="test")
    manager.stage_start(state, "S04")

    info = state.stages["S04"]
    assert info.status == StageStatus.in_progress
    assert info.start_ts


def test_stage_complete(tmp_path) -> None:
    manager = CheckpointManager(tmp_path / "pipeline.json")
    state = PipelineState(topic="test", slug="test")
    manager.stage_complete(state, "S04")

    info = state.stages["S04"]
    assert info.status == StageStatus.completed
    assert info.ts


def test_stage_fail(tmp_path) -> None:
    manager = CheckpointManager(tmp_path / "pipeline.json")
    state = PipelineState(topic="test", slug="test")
    manager.stage_fail(state, "S04")
    assert state.stages["S04"].status == StageStatus.failed


def test_get_resume_stage(tmp_path) -> None:
    manager = CheckpointManager(tmp_path / "pipeline.json")
    state = PipelineState(topic="test", slug="test")
    state.stages["S01"].status = StageStatus.completed
    state.stages["S02"].status = StageStatus.completed
    state.stages["S03"].status = StageStatus.completed
    assert manager.get_resume_stage(state) == 4
