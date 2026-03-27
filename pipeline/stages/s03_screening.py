from __future__ import annotations

from pipeline.core.file_ops import atomic_write
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


class S03Screening(Stage):
    @property
    def name(self) -> str:
        return "S03"

    @property
    def description(self) -> str:
        return "Screening criteria"

    def run(self, ctx: StageContext) -> StageResult:
        template = (
            "# S03 Screening Criteria\n\n"
            "## Inclusion Criteria\n"
            "- Relevant to the defined research question\n"
            "- Sufficient methodological description\n"
            "- Published in credible venues or journals\n\n"
            "## Exclusion Criteria\n"
            "- No direct relevance to the target topic\n"
            "- Insufficient evidence or unclear methods\n"
            "- Duplicate or superseded records\n"
        )
        atomic_write(ctx.state_dir / "s03_screened.md", template)
        return StageResult(content=template)
