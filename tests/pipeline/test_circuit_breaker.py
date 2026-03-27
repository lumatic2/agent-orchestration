from __future__ import annotations

import json
from datetime import datetime, timedelta

from pipeline.sources.circuit_breaker import CircuitBreaker


def test_initial_not_open(tmp_path) -> None:
    cb = CircuitBreaker(tmp_path / "circuit_state.json")
    assert cb.is_open("arxiv") is False


def test_record_failures_opens(tmp_path) -> None:
    cb = CircuitBreaker(tmp_path / "circuit_state.json")
    cb.record_failure("arxiv")
    cb.record_failure("arxiv")
    cb.record_failure("arxiv")
    assert cb.is_open("arxiv") is True


def test_record_success_resets(tmp_path) -> None:
    cb = CircuitBreaker(tmp_path / "circuit_state.json")
    cb.record_failure("arxiv")
    cb.record_failure("arxiv")
    cb.record_failure("arxiv")
    cb.record_success("arxiv")
    assert cb.is_open("arxiv") is False


def test_cooldown_expires(tmp_path) -> None:
    state_file = tmp_path / "circuit_state.json"
    old_ts = (datetime.utcnow() - timedelta(minutes=31)).isoformat()
    state_file.write_text(json.dumps({"arxiv": {"failures": 3, "last_failure": old_ts}}), encoding="utf-8")
    cb = CircuitBreaker(state_file)
    assert cb.is_open("arxiv") is False
