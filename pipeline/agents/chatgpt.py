from __future__ import annotations

from pipeline.agents.base import AgentRunner


class ChatGPTRunner(AgentRunner):
    @property
    def name(self) -> str:
        return "chatgpt"
