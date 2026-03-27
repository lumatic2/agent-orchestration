from __future__ import annotations

import logging
import re
from urllib.parse import quote_plus
from xml.etree import ElementTree as ET

import aiohttp

from pipeline.models.paper import Paper
from pipeline.sources.base import AcademicSource

logger = logging.getLogger(__name__)


class PubmedSource(AcademicSource):
    @property
    def name(self) -> str:
        return "pubmed"

    async def search(self, query: str, max_results: int) -> list[Paper]:
        encoded_query = quote_plus(query)
        esearch_url = (
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
            f"?db=pubmed&term={encoded_query}&retmax={max_results}&retmode=json"
        )
        try:
            timeout = aiohttp.ClientTimeout(total=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(esearch_url) as response:
                    response.raise_for_status()
                    esearch_data = await response.json()
                ids = (esearch_data.get("esearchresult") or {}).get("idlist", [])
                if not ids:
                    return []
                joined_ids = ",".join(ids)
                efetch_url = (
                    "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
                    f"?db=pubmed&id={joined_ids}&rettype=abstract&retmode=xml"
                )
                async with session.get(efetch_url) as response:
                    response.raise_for_status()
                    xml_text = await response.text()

            root = ET.fromstring(xml_text)
            papers: list[Paper] = []
            for article_node in root.findall(".//PubmedArticle"):
                citation = article_node.find("MedlineCitation")
                article = citation.find("Article") if citation is not None else None
                if citation is None or article is None:
                    continue
                title_node = article.find("ArticleTitle")
                title = "".join(title_node.itertext()).strip() if title_node is not None else ""
                authors: list[str] = []
                for author in article.findall("AuthorList/Author"):
                    last = (author.findtext("LastName", "") or "").strip()
                    fore = (author.findtext("ForeName", "") or "").strip()
                    collective = (author.findtext("CollectiveName", "") or "").strip()
                    name = f"{last} {fore}".strip() if (last or fore) else collective
                    if name:
                        authors.append(name)
                year = None
                year_text = (article.findtext("Journal/JournalIssue/PubDate/Year", "") or "").strip()
                if year_text.isdigit():
                    year = int(year_text)
                else:
                    medline_date = (article.findtext("Journal/JournalIssue/PubDate/MedlineDate", "") or "").strip()
                    match = re.search(r"(\d{4})", medline_date)
                    if match:
                        year = int(match.group(1))
                abstract_parts = [
                    "".join(part.itertext()).strip()
                    for part in article.findall("Abstract/AbstractText")
                    if "".join(part.itertext()).strip()
                ]
                abstract = " ".join(abstract_parts)
                doi = None
                for node in article.findall("ELocationID"):
                    if (node.get("EIdType") or "").lower() == "doi" and (node.text or "").strip():
                        doi = (node.text or "").strip()
                        break
                if not doi:
                    for node in article_node.findall(".//ArticleIdList/ArticleId"):
                        if (node.get("IdType") or "").lower() == "doi" and (node.text or "").strip():
                            doi = (node.text or "").strip()
                            break
                pmid = (citation.findtext("PMID", "") or "").strip()
                papers.append(
                    Paper(
                        title=title,
                        authors=authors,
                        year=year,
                        url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/" if pmid else "",
                        doi=doi or None,
                        abstract=abstract,
                        source="pubmed",
                        pmid=pmid or None,
                    )
                )
            return papers
        except Exception as exc:
            logger.warning("PubMed search failed: %s", exc)
            return []
