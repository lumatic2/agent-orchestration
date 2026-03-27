from __future__ import annotations

from datetime import datetime, timedelta

from pipeline.core.watchdog import WatchdogChecker
from pipeline.models.config_schema import PipelineConfig
from pipeline.models.pipeline_state import PipelineState, StageStatus


class _Logger:
    def info(self, _message: str) -> None:
        return None

    def warn(self, _message: str) -> None:
        return None


def _checker() -> WatchdogChecker:
    return WatchdogChecker(PipelineConfig(), _Logger())


def test_no_stale() -> None:
    checker = _checker()
    state = PipelineState(topic="test", slug="test")
    assert checker.check(state) == []


def test_stale_detected() -> None:
    checker = _checker()
    state = PipelineState(topic="test", slug="test")
    state.stages["S04"].status = StageStatus.in_progress
    state.stages["S04"].start_ts = (datetime.now() - timedelta(minutes=15)).isoformat(timespec="seconds")
    assert "S04" in checker.check(state)


def test_skip_stage() -> None:
    checker = _checker()
    state = PipelineState(topic="test", slug="test")
    state.stages["S04"].status = StageStatus.in_progress
    state.stages["S04"].start_ts = (datetime.now() - timedelta(minutes=15)).isoformat(timespec="seconds")
    assert "S04" not in checker.check(state, skip_stage="S04")
