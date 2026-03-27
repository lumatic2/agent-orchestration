from __future__ import annotations

import asyncio
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Awaitable, Iterable

from pipeline.agents.base import AgentResult
from pipeline.agents.fallback import AgentPool
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext

REPO_DIR = Path(__file__).resolve().parent.parent.parent
orch_path = str(REPO_DIR / 'scripts' / 'orchestrate.sh')


def _normalize_verdict(value: str) -> str:
    text = value.strip().lower()
    compact = re.sub(r"[^a-z\s]", "", text)
    compact = re.sub(r"\s+", " ", compact).strip()
    mapping = {
        "sufficient": "sufficient",
        "minor revision": "minor revision",
        "major revision": "major revision",
        "insufficient": "insufficient",
        "minor revisions": "minor revision",
        "major revisions": "major revision",
    }
    if compact in mapping:
        return mapping[compact]
    if "insufficient" in compact:
        return "insufficient"
    if "major" in compact and "revision" in compact:
        return "major revision"
    if "minor" in compact and "revision" in compact:
        return "minor revision"
    if "sufficient" in compact:
        return "sufficient"
    return "major revision"


def _extract_verdict(content: str) -> str:
    for line in content.splitlines():
        if "verdict" not in line.lower():
            continue
        parts = re.split(r":|-", line, maxsplit=1)
        candidate = parts[1] if len(parts) > 1 else line
        return _normalize_verdict(candidate)
    match = re.search(r"\b(sufficient|minor\s+revision|major\s+revision|insufficient)\b", content, flags=re.IGNORECASE)
    if match:
        return _normalize_verdict(match.group(1))
    return "major revision"


def _extract_specific_fixes(content: str) -> list[str]:
    lines = content.splitlines()
    fixes: list[str] = []
    section_start = None
    for idx, line in enumerate(lines):
        if "specific fixes" in line.lower():
            section_start = idx + 1
            break

    if section_start is not None:
        for line in lines[section_start:]:
            lowered = line.strip().lower()
            if not lowered:
                continue
            if lowered.startswith("5.") or "section-by-section" in lowered:
                break
            if re.match(r"^\d+[\.)]\s+", line.strip()):
                fixes.append(re.sub(r"^\d+[\.)]\s+", "", line.strip()))
            elif line.strip().startswith("-"):
                fixes.append(line.strip()[1:].strip())
            elif fixes and line.startswith((" ", "\t")):
                fixes[-1] = f"{fixes[-1]} {line.strip()}".strip()

    if fixes:
        return [f for f in fixes if f]

    generic: list[str] = []
    for line in lines:
        stripped = line.strip()
        if re.match(r"^\d+[\.)]\s+", stripped):
            generic.append(re.sub(r"^\d+[\.)]\s+", "", stripped))
        elif stripped.startswith("-"):
            generic.append(stripped[1:].strip())
    return [f for f in generic if f]


def _strip_meta_commentary(content: str) -> str:
    lines = content.splitlines()
    filtered: list[str] = []
    skip_prefixes = (
        "i have made",
        "here are the",
        "key changes:",
        "changes made:",
    )
    meta_patterns = [
        re.compile(r"^\s*(note|meta|commentary)\s*:", flags=re.IGNORECASE),
        re.compile(r"^\s*(summary of changes|revision summary)\s*:?", flags=re.IGNORECASE),
        re.compile(r"^\s*(this revision|i revised|i updated)\b", flags=re.IGNORECASE),
    ]

    for line in lines:
        stripped = line.strip()
        lowered = stripped.lower()
        if any(lowered.startswith(prefix) for prefix in skip_prefixes):
            continue
        if any(pattern.match(stripped) for pattern in meta_patterns):
            continue
        filtered.append(line)

    cleaned = "\n".join(filtered).strip()
    trailing_headers = [
        "key changes",
        "changes made",
        "meta-commentary",
        "revision notes",
        "notes",
    ]

    for header in trailing_headers:
        marker = re.search(rf"\n+#+\s*{re.escape(header)}\s*$", cleaned, flags=re.IGNORECASE)
        if marker:
            cleaned = cleaned[: marker.start()].rstrip()

    return cleaned


async def _run_agent(
    pool: AgentPool,
    agent_name: str,
    prompt: str,
    task_name: str,
    timeout: int,
) -> AgentResult:
    loop = asyncio.get_event_loop()
    runner = pool.get(agent_name)
    return await loop.run_in_executor(None, runner.run, prompt, task_name, timeout)


async def _gather_reviews(tasks: Iterable[Awaitable[AgentResult]]) -> list[Any]:
    return await asyncio.gather(*tasks, return_exceptions=True)


class S15Validation(Stage):
    @property
    def name(self) -> str:
        return "S15"

    @property
    def description(self) -> str:
        return "Triple-blind validation"

    def run(self, ctx: StageContext) -> StageResult:
        draft = safe_read(ctx.paper_dir / "draft.md")
        draft_truncated = draft[:8000]

        prompt = (
            "You are an expert peer reviewer. Evaluate this academic paper:\n\n"
            f"{draft_truncated}\n\n"
            "Provide:\n"
            "1. VERDICT: Sufficient / Minor Revision / Major Revision / Insufficient\n"
            "2. STRENGTHS (bullet list)\n"
            "3. WEAKNESSES (bullet list)\n"
            "4. SPECIFIC FIXES (numbered list with exact suggestions)\n"
            "5. SECTION-BY-SECTION assessment"
        )

        config = ctx.config
        pool = AgentPool(orch_path)
        timeout_map = {
            "gemini": config.timeouts.agent_gemini,
            "codex": config.timeouts.agent_codex,
            "chatgpt": config.timeouts.agent_chatgpt,
            "claude": config.timeouts.agent_claude,
        }

        reviewers = config.agents.s15_reviewers
        tasks = [
            _run_agent(
                pool,
                name,
                prompt,
                f"s15-{name}-{ctx.slug}",
                timeout_map.get(name.strip().lower(), 180),
            )
            for name in reviewers
        ]
        results = asyncio.run(_gather_reviews(tasks))

        successes: list[tuple[str, AgentResult]] = []
        failures: list[tuple[str, str]] = []

        for name, item in zip(reviewers, results):
            if isinstance(item, Exception):
                atomic_write(ctx.state_dir / f"s15_{name}_review.md", f"Review failed: exception: {item}\n")
                failures.append((name, f"exception: {item}"))
                continue
            result: AgentResult = item
            atomic_write(ctx.state_dir / f"s15_{name}_review.md", result.content)
            if result.exit_code != 0 or result.timed_out or not result.content.strip():
                failure_reason = f"exit_code={result.exit_code}, timed_out={result.timed_out}"
                failures.append((name, failure_reason))
                continue
            successes.append((name, result))

        verdicts = [
            _extract_verdict(result.content)
            for _, result in successes
        ]

        sufficient_threshold = math.ceil((2 * max(len(reviewers), 1)) / 3)
        if verdicts and verdicts.count("sufficient") >= sufficient_threshold:
            final_verdict = "Sufficient"
        elif "insufficient" in verdicts:
            final_verdict = "Insufficient"
        elif verdicts:
            final_verdict = {
                "sufficient": "Sufficient",
                "minor revision": "Minor Revision",
                "major revision": "Major Revision",
                "insufficient": "Insufficient",
            }[Counter(verdicts).most_common(1)[0][0]]
        else:
            final_verdict = "Major Revision"

        all_fixes: list[str] = []
        for _, result in successes:
            all_fixes.extend(_extract_specific_fixes(result.content))
        unique_fixes: list[str] = []
        seen: set[str] = set()
        for fix in all_fixes:
            norm = re.sub(r"\s+", " ", fix.strip().lower())
            if not norm or norm in seen:
                continue
            seen.add(norm)
            unique_fixes.append(fix.strip())

        report_lines = [
            "# S15 Validation",
            "",
            f"- Final Verdict: {final_verdict}",
            f"- Successful Reviews: {len(successes)}/{len(reviewers)}",
        ]

        if failures:
            report_lines.append("- Failed Reviews:")
            for name, reason in failures:
                report_lines.append(f"  - {name}: {reason}")

        report_lines.extend(["", "## Individual Verdicts", ""])
        for name, result in successes:
            report_lines.append(f"- {name}: {_extract_verdict(result.content)}")

        report_lines.extend(["", "## Consolidated Specific Fixes", ""])
        if unique_fixes:
            for idx, fix in enumerate(unique_fixes, 1):
                report_lines.append(f"{idx}. {fix}")
        else:
            report_lines.append("- None extracted")

        report_lines.extend(["", "## Review Excerpts", ""])
        for name, result in successes:
            excerpt = result.content.strip()
            report_lines.append(f"### {name}")
            report_lines.append("")
            report_lines.append(excerpt)
            report_lines.append("")

        if final_verdict in ("Major Revision", "Insufficient"):
            combined_fixes = "\n".join(f"- {fix}" for fix in unique_fixes) if unique_fixes else "- Improve structure, evidence alignment, and clarity."
            revision_prompt = (
                "Revise this paper based on peer review feedback:\n\n"
                f"Original:\n{draft_truncated}\n\n"
                f"Feedback:\n{combined_fixes}\n\n"
                "Output the complete revised paper in markdown. Do NOT include meta-commentary."
            )
            revision_result = pool.get("gemini").run(
                revision_prompt,
                f"s15-revision-{ctx.slug}",
                180,
            )
            if revision_result.exit_code == 0 and not revision_result.timed_out and revision_result.content.strip():
                cleaned_revision = _strip_meta_commentary(revision_result.content)
                atomic_write(ctx.paper_dir / "draft.md", cleaned_revision)
                atomic_write(ctx.state_dir / "s15_revised.md", cleaned_revision)
                report_lines.extend([
                    "",
                    "## Auto Revision",
                    "",
                    "- Revision agent: gemini",
                    "- Revision status: applied",
                ])
            else:
                report_lines.extend([
                    "",
                    "## Auto Revision",
                    "",
                    "- Revision agent: gemini",
                    "- Revision status: failed",
                    f"- exit_code={revision_result.exit_code}, timed_out={revision_result.timed_out}",
                ])

        report = "\n".join(report_lines).rstrip() + "\n"
        atomic_write(ctx.state_dir / "s15_validation.md", report)
        return StageResult(content=report)
