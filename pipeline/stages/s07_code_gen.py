from __future__ import annotations

import re
from pathlib import Path

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext
from pipeline.templates.renderer import render


REPO_DIR = Path(__file__).resolve().parent.parent.parent
orch_path = str(REPO_DIR / 'scripts' / 'orchestrate.sh')
pool = AgentPool(orch_path)


def _extract_code(text: str) -> str:
    match = re.search(r"```[^\n]*\n(.*?)```", text, flags=re.DOTALL)
    if match:
        return match.group(1).strip()
    return text.strip()


class S07CodeGen(Stage):
    @property
    def name(self) -> str:
        return "S07"

    @property
    def description(self) -> str:
        return "Experiment code generation"

    def should_skip(self, ctx: StageContext) -> bool:
        if hasattr(ctx, "skip_experiment"):
            return bool(getattr(ctx, "skip_experiment"))
        return bool(getattr(ctx.config, "skip_experiment", False))

    def run(self, ctx: StageContext) -> StageResult:
        synthesis = safe_read(ctx.state_dir / "s05_synthesis.md")
        experiment = safe_read(ctx.state_dir / "s06_experiment.md")

        try:
            prompt = render(
                REPO_DIR / "templates" / "prompts" / "s07_code_gen.md",
                {"TOPIC": ctx.topic, "SYNTHESIS": synthesis, "EXPERIMENT": experiment},
            )
        except OSError:
            prompt = (
                "Generate Python experiment code:\n\n"
                f"Research: {synthesis}\n\n"
                f"Design: {experiment}\n\n"
                "Output complete executable experiment.py with: data loading, analysis, "
                "visualization, results summary."
            )

        result = run_with_fallback(
            pool=pool,
            primary="codex",
            fallback="chatgpt",
            prompt=prompt,
            task_name=f"s07-code-{ctx.slug}",
            timeout_primary=300,
            timeout_fallback=300,
            logger=ctx.logger,
        )
        code = _extract_code(result.content)
        code_dir = ctx.state_dir / "s07_code"
        code_dir.mkdir(parents=True, exist_ok=True)
        atomic_write(code_dir / "experiment.py", code)
        atomic_write(ctx.state_dir / "s07_code_gen.md", result.content)
        return StageResult(content=code)
