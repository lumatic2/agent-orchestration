from __future__ import annotations

import asyncio
import re
from pathlib import Path

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.paper import Paper
from pipeline.models.stage_result import StageResult
from pipeline.sources.arxiv import ArxivSource
from pipeline.sources.base import AcademicSource
from pipeline.sources.circuit_breaker import CircuitBreaker
from pipeline.sources.dedup import deduplicate
from pipeline.sources.openalex import OpenAlexSource
from pipeline.sources.pubmed import PubmedSource
from pipeline.sources.semantic_scholar import SemanticScholarSource
from pipeline.stages.base import Stage, StageContext


def _contains_korean(text: str) -> bool:
    return bool(re.search(r"[가-힣]", text))


def _extract_keywords(scope_text: str) -> str:
    if not scope_text.strip():
        return ""
    lines = scope_text.splitlines()
    in_keywords = False
    collected: list[str] = []
    for raw in lines:
        line = raw.strip()
        if line.startswith("## "):
            heading = line[3:].strip().lower()
            in_keywords = "keyword" in heading or "키워드" in heading
            continue
        if not in_keywords:
            continue
        value = line.lstrip("-").strip()
        if value:
            collected.append(value)
    return ", ".join(collected).strip()


async def _search_source(
    source: AcademicSource,
    query: str,
    max_results: int,
    cb: CircuitBreaker,
) -> list[Paper]:
    if cb.is_open(source.name):
        return []
    try:
        papers = await source.search(query, max_results)
        cb.record_success(source.name)
        return papers
    except Exception:
        cb.record_failure(source.name)
        return []


async def _search_all(
    sources: list[tuple[AcademicSource, int]],
    query: str,
    cb: CircuitBreaker,
) -> list[Paper]:
    tasks = [_search_source(source, query, max_results, cb) for source, max_results in sources]
    results = await asyncio.gather(*tasks, return_exceptions=False)
    all_papers: list[Paper] = []
    for papers in results:
        all_papers.extend(papers)
    return all_papers


class S02Literature(Stage):
    @property
    def name(self) -> str:
        return "S02"

    @property
    def description(self) -> str:
        return "Literature search"

    def run(self, ctx: StageContext) -> StageResult:
        scope_text = safe_read(ctx.state_dir / "s01_scope.md")
        query = _extract_keywords(scope_text) or ctx.topic

        repo_dir = Path(__file__).resolve().parent.parent.parent
        orch_path = repo_dir / "scripts" / "orchestrate.sh"
        pool = AgentPool(str(orch_path))

        if _contains_korean(f"{ctx.topic}\n{query}"):
            routing = ctx.config.agents.s02_keywords
            translated = run_with_fallback(
                pool,
                routing.primary,
                routing.fallback,
                f"Translate to English academic keywords: {ctx.topic}",
                f"s02-keywords-{ctx.slug}",
                60,
                60,
                ctx.logger,
            )
            if translated.content.strip():
                query = translated.content.strip()

        sources: list[tuple[AcademicSource, int]] = [
            (ArxivSource(), ctx.config.api.arxiv_max),
            (SemanticScholarSource(), ctx.config.api.ss_max),
            (OpenAlexSource(), ctx.config.api.openalex_max),
            (PubmedSource(), ctx.config.api.pubmed_max),
        ]
        cb = CircuitBreaker(ctx.state_dir / "circuit_state.json")
        all_papers = asyncio.run(_search_all(sources, query, cb))
        deduped = deduplicate(all_papers)

        lines = [
            "# S02 Literature Search",
            "",
            f"## Query",
            f"- {query}",
            "",
            "## Papers",
        ]
        if not deduped:
            lines.extend(["", "<!-- WARNING: No papers found -->"])
        else:
            for paper in deduped:
                lines.extend(["", paper.to_markdown()])
        markdown = "\n".join(lines).strip() + "\n"

        atomic_write(ctx.state_dir / "s02_literature.md", markdown)
        return StageResult(content=markdown)
