from __future__ import annotations

import asyncio
from unittest.mock import patch

import aiohttp

from pipeline.sources.arxiv import ArxivSource
from pipeline.sources.openalex import OpenAlexSource
from pipeline.sources.pubmed import PubmedSource
from pipeline.sources.semantic_scholar import SemanticScholarSource


ARXIV_XML = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
  <entry>
    <id>http://arxiv.org/abs/1234.5678v1</id>
    <title>First Arxiv Paper</title>
    <summary>First abstract</summary>
    <published>2023-01-01T00:00:00Z</published>
    <author><name>Alice</name></author>
    <author><name>Bob</name></author>
    <arxiv:doi>10.1000/arxiv.1</arxiv:doi>
  </entry>
  <entry>
    <id>http://arxiv.org/abs/9999.0001v2</id>
    <title>Second Arxiv Paper</title>
    <summary>Second abstract</summary>
    <published>2022-05-03T00:00:00Z</published>
    <author><name>Carol</name></author>
    <link href="https://doi.org/10.1000/arxiv.2" title="doi" />
  </entry>
</feed>
"""

PUBMED_EFETCH_XML = """<?xml version="1.0" encoding="UTF-8"?>
<PubmedArticleSet>
  <PubmedArticle>
    <MedlineCitation>
      <PMID>111</PMID>
      <Article>
        <ArticleTitle>First PubMed Paper</ArticleTitle>
        <AuthorList><Author><LastName>Kim</LastName><ForeName>A</ForeName></Author></AuthorList>
        <Journal><JournalIssue><PubDate><Year>2021</Year></PubDate></JournalIssue></Journal>
        <Abstract><AbstractText>First abstract</AbstractText></Abstract>
        <ELocationID EIdType="doi">10.1000/pubmed.1</ELocationID>
      </Article>
    </MedlineCitation>
  </PubmedArticle>
  <PubmedArticle>
    <MedlineCitation>
      <PMID>222</PMID>
      <Article>
        <ArticleTitle>Second PubMed Paper</ArticleTitle>
        <AuthorList><Author><LastName>Lee</LastName><ForeName>B</ForeName></Author></AuthorList>
        <Journal><JournalIssue><PubDate><Year>2020</Year></PubDate></JournalIssue></Journal>
        <Abstract><AbstractText>Second abstract</AbstractText></Abstract>
      </Article>
    </MedlineCitation>
  </PubmedArticle>
</PubmedArticleSet>
"""


class _FakeResponse:
    def __init__(self, *, text_data: str | None = None, json_data: dict | None = None) -> None:
        self._text_data = text_data
        self._json_data = json_data

    async def __aenter__(self) -> _FakeResponse:
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def raise_for_status(self) -> None:
        return None

    async def text(self) -> str:
        return self._text_data or ""

    async def json(self) -> dict:
        return self._json_data or {}


class _FakeSession:
    def __init__(self, responses: list[object]) -> None:
        self._responses = responses

    async def __aenter__(self) -> _FakeSession:
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def get(self, _url: str):
        next_item = self._responses.pop(0)
        if isinstance(next_item, Exception):
            raise next_item
        return next_item


def test_arxiv_parse() -> None:
    fake = _FakeSession([_FakeResponse(text_data=ARXIV_XML)])
    with patch("pipeline.sources.arxiv.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(ArxivSource().search("llm", 2))
    assert len(papers) == 2
    assert papers[0].title == "First Arxiv Paper"
    assert papers[0].authors == ["Alice", "Bob"]
    assert papers[0].doi == "10.1000/arxiv.1"
    assert papers[1].doi == "10.1000/arxiv.2"


def test_arxiv_empty() -> None:
    fake = _FakeSession([_FakeResponse(text_data="")])
    with patch("pipeline.sources.arxiv.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(ArxivSource().search("llm", 2))
    assert papers == []


def test_arxiv_error() -> None:
    fake = _FakeSession([aiohttp.ClientConnectionError("boom")])
    with patch("pipeline.sources.arxiv.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(ArxivSource().search("llm", 2))
    assert papers == []


def test_ss_parse() -> None:
    payload = {
        "data": [
            {
                "title": "SS Paper",
                "authors": [{"name": "Alice"}],
                "year": 2024,
                "externalIds": {"DOI": "10.1000/ss.1"},
                "abstract": "SS abstract",
                "url": "https://ss/p1",
            }
        ]
    }
    fake = _FakeSession([_FakeResponse(json_data=payload)])
    with patch("pipeline.sources.semantic_scholar.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(SemanticScholarSource().search("llm", 1))
    assert len(papers) == 1
    assert papers[0].title == "SS Paper"
    assert papers[0].authors == ["Alice"]
    assert papers[0].doi == "10.1000/ss.1"


def test_ss_error() -> None:
    fake = _FakeSession([aiohttp.ClientConnectionError("boom")])
    with patch("pipeline.sources.semantic_scholar.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(SemanticScholarSource().search("llm", 1))
    assert papers == []


def test_pubmed_parse() -> None:
    esearch_json = {"esearchresult": {"idlist": ["111", "222"]}}
    fake = _FakeSession([_FakeResponse(json_data=esearch_json), _FakeResponse(text_data=PUBMED_EFETCH_XML)])
    with patch("pipeline.sources.pubmed.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(PubmedSource().search("llm", 2))
    assert len(papers) == 2
    assert papers[0].pmid == "111"
    assert papers[1].pmid == "222"


def test_pubmed_no_results() -> None:
    esearch_json = {"esearchresult": {"idlist": []}}
    fake = _FakeSession([_FakeResponse(json_data=esearch_json)])
    with patch("pipeline.sources.pubmed.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(PubmedSource().search("llm", 2))
    assert papers == []


def test_openalex_parse() -> None:
    payload = {
        "results": [
            {
                "display_name": "OpenAlex Paper",
                "authorships": [{"author": {"display_name": "Alice"}}],
                "publication_year": 2023,
                "doi": "https://doi.org/10.1000/oa.1",
                "id": "https://openalex.org/W1",
            }
        ]
    }
    fake = _FakeSession([_FakeResponse(json_data=payload)])
    with patch("pipeline.sources.openalex.aiohttp.ClientSession", return_value=fake):
        papers = asyncio.run(OpenAlexSource().search("llm", 1))
    assert len(papers) == 1
    assert papers[0].title == "OpenAlex Paper"
    assert papers[0].authors == ["Alice"]
    assert papers[0].doi == "10.1000/oa.1"
