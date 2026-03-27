from __future__ import annotations

from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


class S12QualityGate(Stage):
    @property
    def name(self) -> str:
        return "S12"

    @property
    def description(self) -> str:
        return "Quality gate"

    def run(self, ctx: StageContext) -> StageResult:
        revised = safe_read(ctx.state_dir / "s11_revised.md")
        checklist = (
            "# S12 Quality Gate\n\n"
            "## S11 Revised Snapshot\n"
            f"{revised}\n\n"
            "## Checklist\n"
            "- [ ] Structure check\n"
            "- [ ] Reference check\n"
            "- [ ] Methodology check\n"
            "- [ ] Evidence-to-claim consistency\n"
            "- [ ] Bias and limitation disclosure\n"
            "- [ ] Reproducibility and transparency\n"
            "- [ ] Decision readiness\n"
        )
        atomic_write(ctx.state_dir / "s12_quality.md", checklist)
        return StageResult(content=checklist, gate_required=True)
