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


class S11PeerReview(Stage):
    @property
    def name(self) -> str:
        return "S11"

    @property
    def description(self) -> str:
        return "Peer review"

    def run(self, ctx: StageContext) -> StageResult:
        draft = safe_read(ctx.paper_dir / "draft.md")
        limit = ctx.config.thresholds.payload_truncate_s11
        draft = draft[:limit]

        try:
            prompt = render(
                REPO_DIR / "templates" / "prompts" / "s11_peer_review.md",
                {"TOPIC": ctx.topic, "DRAFT": draft},
            )
        except OSError:
            prompt = (
                "You are a peer reviewer. Review this academic paper draft:\n\n"
                f"Topic: {ctx.topic}\n\n"
                f"{draft}\n\n"
                "Provide:\n"
                "1. Strengths\n"
                "2. Weaknesses (with specific line references)\n"
                "3. SECTION_ADDITION blocks for missing content\n"
                "4. Suggested revisions\n"
                "5. Overall assessment"
            )

        fallback = ctx.config.agents.s11.fallback
        result = run_with_fallback(
            pool,
            ctx.config.agents.s11.primary,
            fallback,
            prompt,
            f"s11-review-{ctx.slug}",
            ctx.config.timeouts.agent_gemini,
            ctx.config.timeouts.agent_chatgpt,
            ctx.logger,
        )
        atomic_write(ctx.state_dir / "s11_revised.md", result.content)
        return StageResult(content=result.content)
