from __future__ import annotations

import asyncio
import re
from pathlib import Path
from urllib.parse import quote

import aiohttp

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


REPO_DIR = Path(__file__).resolve().parent.parent.parent
orch_path = str(REPO_DIR / "scripts" / "orchestrate.sh")
pool = AgentPool(orch_path)


class S14CitationVerify(Stage):
    @property
    def name(self) -> str:
        return "S14"

    @property
    def description(self) -> str:
        return "Citation verification"

    async def _check_url(
        self,
        session: aiohttp.ClientSession,
        url: str,
        timeout: int = 8,
    ) -> tuple[str, bool]:
        try:
            request_timeout = aiohttp.ClientTimeout(total=timeout)
            async with session.head(url, timeout=request_timeout, allow_redirects=True) as response:
                return (url, response.status < 400)
        except Exception:
            return (url, False)

    async def _check_doi(
        self,
        session: aiohttp.ClientSession,
        doi: str,
        timeout: int = 8,
    ) -> tuple[str, bool]:
        encoded = quote(doi, safe="")
        target = f"https://api.semanticscholar.org/graph/v1/paper/DOI:{encoded}?fields=title"
        try:
            request_timeout = aiohttp.ClientTimeout(total=timeout)
            async with session.get(target, timeout=request_timeout) as response:
                if response.status >= 400:
                    return (doi, False)
                payload = await response.json(content_type=None)
                return (doi, bool(payload.get("title")))
        except Exception:
            return (doi, False)

    async def _verify_refs(
        self,
        urls: list[str],
        dois: list[str],
    ) -> tuple[list[tuple[str, bool]], list[tuple[str, bool]]]:
        connector = aiohttp.TCPConnector(limit=20, ssl=False)
        async with aiohttp.ClientSession(connector=connector) as session:
            url_tasks = [self._check_url(session, url) for url in urls]
            doi_tasks = [self._check_doi(session, doi) for doi in dois]
            url_results, doi_results = await asyncio.gather(
                asyncio.gather(*url_tasks),
                asyncio.gather(*doi_tasks),
            )
            return (list(url_results), list(doi_results))

    def run(self, ctx: StageContext) -> StageResult:
        draft = safe_read(ctx.paper_dir / "draft.md")
        urls = re.findall(r"https?://[^\s\)\]>]+", draft)
        dois = re.findall(r"10\.\d{4,}/[^\s\)\]>]+", draft)

        try:
            url_results, doi_results = asyncio.run(self._verify_refs(urls, dois))
        except RuntimeError:
            loop = asyncio.new_event_loop()
            try:
                asyncio.set_event_loop(loop)
                url_results, doi_results = loop.run_until_complete(self._verify_refs(urls, dois))
            finally:
                loop.close()
                asyncio.set_event_loop(None)

        broken_urls = [url for url, ok in url_results if not ok]
        unresolved_dois = [doi for doi, ok in doi_results if not ok]

        truncated = draft[:4000]
        prompt = (
            "Verify citations in this paper. List any: incorrect citations, missing references, "
            f"inconsistent numbering.\n\n{truncated}"
        )
        fallback = ctx.config.agents.s14.fallback
        consistency = run_with_fallback(
            pool=pool,
            primary="gemini",
            fallback=fallback,
            prompt=prompt,
            task_name=f"s14-citation-{ctx.slug}",
            timeout_primary=ctx.config.timeouts.agent_gemini,
            timeout_fallback=ctx.config.timeouts.agent_gemini,
            logger=ctx.logger,
        )

        total_refs = len(urls) + len(dois)
        unverified = len(broken_urls) + len(unresolved_dois)
        unverified_rate = (unverified / total_refs * 100.0) if total_refs else 0.0
        gate_flag = unverified_rate > ctx.config.thresholds.s14_unverified_rate_gate

        lines = [
            "# S14 Citation Verification",
            "",
            "## Summary",
            f"- Total references: {total_refs}",
            f"- URL count: {len(urls)}",
            f"- DOI count: {len(dois)}",
            f"- Broken URLs: {len(broken_urls)}",
            f"- Unresolved DOIs: {len(unresolved_dois)}",
            f"- Unverified rate: {unverified_rate:.2f}%",
            f"- Gate required: {gate_flag}",
            "",
            "## Broken URLs",
        ]
        if broken_urls:
            lines.extend([f"- {item}" for item in broken_urls])
        else:
            lines.append("- None")
        lines.extend(["", "## Unresolved DOIs"])
        if unresolved_dois:
            lines.extend([f"- {item}" for item in unresolved_dois])
        else:
            lines.append("- None")
        lines.extend(["", "## Gemini Consistency Check", consistency.content.strip() or "(empty)"])
        report = "\n".join(lines).strip() + "\n"

        atomic_write(ctx.state_dir / "s14_citations.md", report)
        return StageResult(content=report, gate_required=gate_flag)
