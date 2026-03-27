from __future__ import annotations

from pipeline.agents.base import AgentResult, AgentRunner
from pipeline.agents.chatgpt import ChatGPTRunner
from pipeline.agents.claude import ClaudeRunner
from pipeline.agents.codex import CodexRunner
from pipeline.agents.gemini import GeminiRunner
from pipeline.core.logging import PipelineLogger


class AgentPool:
    def __init__(self, orch_path: str) -> None:
        self.runners: dict[str, AgentRunner] = {
            "gemini": GeminiRunner(orch_path),
            "codex": CodexRunner(orch_path),
            "chatgpt": ChatGPTRunner(orch_path),
            "claude": ClaudeRunner(orch_path),
        }

    def get(self, name: str) -> AgentRunner:
        key = name.strip().lower()
        if key not in self.runners:
            raise KeyError(f"Unknown agent: {name}")
        return self.runners[key]


def _is_failed(result: AgentResult) -> bool:
    return result.exit_code != 0 or result.timed_out or result.content.strip() == ""


def run_with_fallback(
    pool: AgentPool,
    primary: str,
    fallback: str | None,
    prompt: str,
    task_name: str,
    timeout_primary: int,
    timeout_fallback: int | None = None,
    logger: PipelineLogger | None = None,
) -> AgentResult:
    if logger:
        logger.info(f"Attempt primary agent: {primary}")
    primary_runner = pool.get(primary)
    primary_result = primary_runner.run(prompt, task_name, timeout_primary)

    if not _is_failed(primary_result):
        return primary_result

    if logger:
        logger.warn(f"Primary agent failed: {primary}")

    if not fallback:
        return primary_result

    fallback_timeout = timeout_fallback if timeout_fallback is not None else timeout_primary
    if logger:
        logger.info(f"Attempt fallback agent: {fallback}")
    fallback_runner = pool.get(fallback)
    fallback_result = fallback_runner.run(prompt, task_name, fallback_timeout)

    if _is_failed(fallback_result) and logger:
        logger.warn(f"Fallback agent failed: {fallback}")

    return fallback_result
