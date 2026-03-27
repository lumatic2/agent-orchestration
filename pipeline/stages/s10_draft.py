from __future__ import annotations

from pathlib import Path

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.templates.renderer import render


REPO_DIR = Path(__file__).resolve().parent.parent.parent
orch_path = str(REPO_DIR / 'scripts' / 'orchestrate.sh')
pool = AgentPool(orch_path)


class S10Draft(Stage):
    @property
    def name(self) -> str:
        return "S10"

    @property
    def description(self) -> str:
        return "Paper draft generation"

    def run(self, ctx: StageContext) -> StageResult:
        synthesis = safe_read(ctx.state_dir / "s05_synthesis.md")
        limit = ctx.config.thresholds.payload_truncate
        synthesis = synthesis[:limit]

        try:
            prompt = render(
                REPO_DIR / "templates" / "prompts" / "s10_paper_draft.md",
                {"TOPIC": ctx.topic, "SYNTHESIS": synthesis},
            )
        except OSError:
            prompt = (
                "Write a complete academic paper draft in markdown:\n\n"
                f"Topic: {ctx.topic}\n\n"
                f"Research synthesis:\n{synthesis}\n\n"
                "Include: Title, Abstract, 1. Introduction, 2. Background, 3. Methodology, "
                "4. Analysis, 5. Discussion, 6. Conclusion, References.\n"
                "Use formal academic tone. Write section content in detail (not outlines)."
            )

        fallback = ctx.config.agents.s10.fallback
        result = run_with_fallback(
            pool,
            ctx.config.agents.s10.primary,
            fallback,
            prompt,
            f"s10-draft-{ctx.slug}",
            ctx.config.timeouts.agent_gemini,
            ctx.config.timeouts.agent_chatgpt,
            ctx.logger,
        )
        atomic_write(ctx.paper_dir / "draft.md", result.content)
        atomic_write(ctx.state_dir / "s10_draft.md", result.content)
        return StageResult(content=result.content)
