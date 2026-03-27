from __future__ import annotations

from pathlib import Path

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.templates.renderer import render


class S05Synthesis(Stage):
    @property
    def name(self) -> str:
        return "S05"

    @property
    def description(self) -> str:
        return "Research synthesis"

    def run(self, ctx: StageContext) -> StageResult:
        extracted = safe_read(ctx.state_dir / "s04_extracted.md")
        truncated = extracted[: ctx.config.thresholds.payload_truncate]

        repo_dir = Path(__file__).resolve().parent.parent.parent
        orch_path = repo_dir / "scripts" / "orchestrate.sh"
        pool = AgentPool(str(orch_path))

        template_path = repo_dir / ctx.config.templates.prompts_dir / "s05_synthesis.md"
        if template_path.exists():
            prompt = render(
                template_path,
                {
                    "TOPIC": ctx.topic,
                    "EXTRACTED": truncated,
                },
            )
        else:
            prompt = (
                "Synthesize extracted knowledge and identify research gaps:\n\n"
                f"Topic: {ctx.topic}\n\n"
                f"{truncated}\n\n"
                "Provide: synthesis, gaps, unique contributions."
            )

        result = run_with_fallback(
            pool,
            ctx.config.agents.s05.primary,
            ctx.config.agents.s05.fallback,
            prompt,
            f"s05-synth-{ctx.slug}",
            ctx.config.timeouts.agent_gemini,
            ctx.config.timeouts.agent_chatgpt,
            ctx.logger,
        )

        atomic_write(ctx.state_dir / "s05_synthesis.md", result.content)
        return StageResult(content=result.content)
