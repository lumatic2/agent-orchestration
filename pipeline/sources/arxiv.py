from __future__ import annotations

import logging
from urllib.parse import quote_plus
from xml.etree import ElementTree as ET

import aiohttp

from pipeline.models.paper import Paper
from pipeline.sources.base import AcademicSource

logger = logging.getLogger(__name__)


class ArxivSource(AcademicSource):
    @property
    def name(self) -> str:
        return "arxiv"

    async def search(self, query: str, max_results: int) -> list[Paper]:
        encoded_query = quote_plus(query)
        url = (
            "http://export.arxiv.org/api/query"
            f"?search_query=all:{encoded_query}&max_results={max_results}"
        )
        try:
            timeout = aiohttp.ClientTimeout(total=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    response.raise_for_status()
                    xml_text = await response.text()

            root = ET.fromstring(xml_text)
            ns = {"atom": "http://www.w3.org/2005/Atom", "arxiv": "http://arxiv.org/schemas/atom"}
            papers: list[Paper] = []
            for entry in root.findall("atom:entry", ns):
                title = (entry.findtext("atom:title", "", ns) or "").strip()
                authors = [
                    (node.text or "").strip()
                    for node in entry.findall("atom:author/atom:name", ns)
                    if (node.text or "").strip()
                ]
                published = (entry.findtext("atom:published", "", ns) or "").strip()
                year = int(published[:4]) if len(published) >= 4 and published[:4].isdigit() else None
                paper_url = (entry.findtext("atom:id", "", ns) or "").strip()
                abstract = (entry.findtext("atom:summary", "", ns) or "").strip()
                doi = None
                doi_node = entry.find("arxiv:doi", ns)
                if doi_node is not None and doi_node.text:
                    doi = doi_node.text.strip()
                if not doi:
                    for link in entry.findall("atom:link", ns):
                        if (link.get("title") or "").strip().lower() == "doi":
                            href = (link.get("href") or "").strip()
                            doi = href.replace("https://doi.org/", "").replace("http://doi.org/", "")
                            break
                papers.append(
                    Paper(
                        title=title,
                        authors=authors,
                        year=year,
                        url=paper_url,
                        doi=doi or None,
                        abstract=abstract,
                        source="arxiv",
                    )
                )
            return papers
        except Exception as exc:
            logger.warning("arXiv search failed: %s", exc)
            return []
