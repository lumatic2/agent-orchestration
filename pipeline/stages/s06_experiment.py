from __future__ import annotations

from pipeline.core.file_ops import atomic_write
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


class S06Experiment(Stage):
    @property
    def name(self) -> str:
        return "S06"

    @property
    def description(self) -> str:
        return "Experiment design"

    def should_skip(self, ctx: StageContext) -> bool:
        return bool(getattr(ctx.config, "skip_experiment", False))

    def run(self, ctx: StageContext) -> StageResult:
        template = (
            "# S06 Experiment Design\n\n"
            "## Objective\n"
            "- \n\n"
            "## Hypothesis\n"
            "- \n\n"
            "## Dataset / Sources\n"
            "- \n\n"
            "## Method\n"
            "- \n\n"
            "## Metrics\n"
            "- \n\n"
            "## Risks\n"
            "- \n"
        )
        atomic_write(ctx.state_dir / "s06_experiment.md", template)
        return StageResult(content=template, gate_required=True)
