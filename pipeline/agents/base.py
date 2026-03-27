from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class AgentResult:
    content: str
    raw_output: str
    exit_code: int
    agent_name: str
    elapsed_seconds: float
    timed_out: bool = False


class AgentRunner(ABC):
    @property
    @abstractmethod
    def name(self) -> str:
        """Return the stable agent name."""

    @abstractmethod
    def run(self, prompt: str, task_name: str, timeout: int) -> AgentResult:
        """Execute an agent task and return structured output."""
