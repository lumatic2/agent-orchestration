from __future__ import annotations

import logging
from urllib.parse import quote_plus

import aiohttp

from pipeline.models.paper import Paper
from pipeline.sources.base import AcademicSource

logger = logging.getLogger(__name__)


class SemanticScholarSource(AcademicSource):
    @property
    def name(self) -> str:
        return "semantic_scholar"

    async def search(self, query: str, max_results: int) -> list[Paper]:
        encoded_query = quote_plus(query)
        url = (
            "https://api.semanticscholar.org/graph/v1/paper/search"
            f"?query={encoded_query}&limit={max_results}"
            "&fields=title,authors,year,externalIds,abstract,url"
        )
        try:
            timeout = aiohttp.ClientTimeout(total=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    response.raise_for_status()
                    payload = await response.json()
            papers: list[Paper] = []
            for item in payload.get("data", []):
                authors = [
                    (author.get("name") or "").strip()
                    for author in item.get("authors", [])
                    if (author.get("name") or "").strip()
                ]
                doi = (item.get("externalIds") or {}).get("DOI")
                papers.append(
                    Paper(
                        title=(item.get("title") or "").strip(),
                        authors=authors,
                        year=item.get("year"),
                        url=(item.get("url") or "").strip(),
                        doi=doi.strip() if isinstance(doi, str) and doi.strip() else None,
                        abstract=(item.get("abstract") or "").strip(),
                        source="semantic_scholar",
                    )
                )
            return papers
        except Exception as exc:
            logger.warning("Semantic Scholar search failed: %s", exc)
            return []
