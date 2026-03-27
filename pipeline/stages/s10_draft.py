from __future__ import annotations

from pathlib import Path
from pipeline.core.platform import get_orch_path, get_repo_dir

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.templates.renderer import render


from pipeline.core.platform import get_orch_path, get_repo_dir
ORCH_PATH = get_orch_path()
pool = AgentPool(ORCH_PATH)


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
                get_repo_dir() / "templates" / "prompts" / "s10_paper_draft.md",
                {"TOPIC": ctx.topic, "SYNTHESIS": synthesis},
            )
        except OSError:
            prompt = (
                "Write a complete academic paper draft in markdown.\n\n"
                "IMPORTANT FORMAT RULES:\n"
                "- Start with: # [논문 제목]\n"
                "- Then: ## 초록\n"
                "- Then sections: ## 1. 서론, ## 2. 이론적 배경, ## 3. 연구 방법, "
                "## 4. 연구 결과, ## 5. 고찰, ## 6. 결론, ## 후속 연구 제안, ## 참고문헌\n"
                "- Use ## for all section headings (not ### or #)\n"
                "- Write in Korean. Formal academic tone. Detailed content (not outlines).\n\n"
                f"Topic: {ctx.topic}\n\n"
                f"Research synthesis:\n{synthesis}"
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
