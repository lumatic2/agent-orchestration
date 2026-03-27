from __future__ import annotations

from pipeline.agents.base import AgentRunner


class GeminiRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "gemini"
