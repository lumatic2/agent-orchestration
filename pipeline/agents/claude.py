from __future__ import annotations

from pipeline.agents.base import AgentRunner


class ClaudeRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "claude"
