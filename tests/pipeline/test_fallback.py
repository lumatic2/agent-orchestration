from __future__ import annotations

from pipeline.agents.base import AgentResult, AgentRunner
from pipeline.agents.fallback import run_with_fallback


class MockRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "mock"

    def run(self, prompt: str, task_name: str, timeout: int) -> AgentResult:
        del prompt, task_name, timeout
        return AgentResult(
            content="ok",
            raw_output="ok",
            exit_code=0,
            agent_name="mock",
            elapsed_seconds=1.0,
        )


class FailRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "fail"

    def run(self, prompt: str, task_name: str, timeout: int) -> AgentResult:
        del prompt, task_name, timeout
        return AgentResult(
            content="",
            raw_output="fail",
            exit_code=1,
            agent_name="fail",
            elapsed_seconds=1.0,
        )


class _Pool:
    def __init__(self, runners: dict[str, AgentRunner]) -> None:
        self.runners = runners

    def get(self, name: str) -> AgentRunner:
        return self.runners[name]


def test_primary_success() -> None:
    pool = _Pool({"primary": MockRunner(), "fallback": MockRunner()})
    result = run_with_fallback(pool, "primary", "fallback", "prompt", "task", 10)
    assert result.exit_code == 0
    assert result.agent_name == "mock"


def test_fallback_on_fail() -> None:
    pool = _Pool({"primary": FailRunner(), "fallback": MockRunner()})
    result = run_with_fallback(pool, "primary", "fallback", "prompt", "task", 10)
    assert result.exit_code == 0
    assert result.agent_name == "mock"


def test_both_fail() -> None:
    pool = _Pool({"primary": FailRunner(), "fallback": FailRunner()})
    result = run_with_fallback(pool, "primary", "fallback", "prompt", "task", 10)
    assert result.exit_code != 0
