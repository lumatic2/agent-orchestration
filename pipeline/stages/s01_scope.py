from __future__ import annotations

from pipeline.core.file_ops import atomic_write
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


class S01Scope(Stage):
    @property
    def name(self) -> str:
        return "S01"

    @property
    def description(self) -> str:
        return "Research scope definition"

    def run(self, ctx: StageContext) -> StageResult:
        template = (
            f"# S01 Scope Definition\n\n"
            f"## Topic\n"
            f"- {ctx.topic}\n\n"
            f"## Research Questions (RQ)\n"
            f"- RQ1:\n"
            f"- RQ2:\n"
            f"- RQ3:\n\n"
            f"## 영문 검색 키워드\n"
            f"- \n\n"
            f"## 한글 검색 키워드\n"
            f"- \n"
        )
        atomic_write(ctx.state_dir / "s01_scope.md", template)
        return StageResult(content=template)
