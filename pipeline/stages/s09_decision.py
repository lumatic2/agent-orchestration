from __future__ import annotations

from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


class S09Decision(Stage):
    @property
    def name(self) -> str:
        return "S09"

    @property
    def description(self) -> str:
        return "Experiment decision"

    def should_skip(self, ctx: StageContext) -> bool:
        return bool(ctx.skip_experiment)

    def run(self, ctx: StageContext) -> StageResult:
        results = safe_read(ctx.state_dir / "s08_results.md")
        template = (
            "# S09 Decision\n\n"
            "## S08 Results Summary\n"
            f"{results}\n\n"
            "## Decision\n"
            "- PROCEED / REFINE / PIVOT\n"
            "- Rationale:\n"
        )
        atomic_write(ctx.state_dir / "s09_decision.md", template)
        return StageResult(content=results, decision_required=True)
