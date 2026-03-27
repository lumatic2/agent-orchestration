from __future__ import annotations

import logging
from urllib.parse import quote_plus

import aiohttp

from pipeline.models.paper import Paper
from pipeline.sources.base import AcademicSource

logger = logging.getLogger(__name__)


class OpenAlexSource(AcademicSource):
    @property
    def name(self) -> str:
        return "openalex"

    async def search(self, query: str, max_results: int) -> list[Paper]:
        encoded_query = quote_plus(query)
        url = (
            "https://api.openalex.org/works"
            f"?search={encoded_query}&per_page={max_results}"
            "&select=id,display_name,authorships,publication_year,doi,open_access"
        )
        try:
            timeout = aiohttp.ClientTimeout(total=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    response.raise_for_status()
                    payload = await response.json()
            papers: list[Paper] = []
            for item in payload.get("results", []):
                authors = []
                for authorship in item.get("authorships", []):
                    name = ((authorship.get("author") or {}).get("display_name") or "").strip()
                    if name:
                        authors.append(name)
                doi = (item.get("doi") or "").strip()
                if doi:
                    doi = doi.replace("https://doi.org/", "").replace("http://doi.org/", "")
                papers.append(
                    Paper(
                        title=(item.get("display_name") or "").strip(),
                        authors=authors,
                        year=item.get("publication_year"),
                        url=(item.get("id") or "").strip(),
                        doi=doi or None,
                        abstract="",
                        source="openalex",
                    )
                )
            return papers
        except Exception as exc:
            logger.warning("OpenAlex search failed: %s", exc)
            return []
