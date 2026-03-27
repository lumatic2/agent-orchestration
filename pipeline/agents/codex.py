from __future__ import annotations

from pipeline.agents.base import AgentRunner


class CodexRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "codex"
