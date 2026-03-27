from __future__ import annotations

from abc import ABC, abstractmethod

from pipeline.models.paper import Paper


class AcademicSource(ABC):
    @property
    @abstractmethod
    def name(self) -> str:
        """Return the source identifier."""

    @abstractmethod
    async def search(self, query: str, max_results: int) -> list[Paper]:
        """Search papers for a query and return normalized results."""
