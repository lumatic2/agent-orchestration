from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

from pipeline.agents.fallback import AgentPool, run_with_fallback
from pipeline.core.file_ops import atomic_write, safe_read
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


REPO_DIR = Path(__file__).resolve().parent.parent.parent
orch_path = str(REPO_DIR / 'scripts' / 'orchestrate.sh')
pool = AgentPool(orch_path)


def _classify_error(stderr: str) -> str:
    if "ModuleNotFoundError" in stderr or "ImportError" in stderr:
        return "IMPORT_ERROR"
    if "SyntaxError" in stderr:
        return "SYNTAX_ERROR"
    return "RUNTIME_ERROR"


def _extract_code(text: str) -> str:
    match = re.search(r"```[^\n]*\n(.*?)```", text, flags=re.DOTALL)
    if match:
        return match.group(1).strip()
    return text.strip()


class S08ExperimentRun(Stage):
    @property
    def name(self) -> str:
        return "S08"

    @property
    def description(self) -> str:
        return "Experiment execution"

    def should_skip(self, ctx: StageContext) -> bool:
        if hasattr(ctx, "skip_experiment"):
            return bool(getattr(ctx, "skip_experiment"))
        return bool(getattr(ctx.config, "skip_experiment", False))

    def run(self, ctx: StageContext) -> StageResult:
        code_dir = ctx.state_dir / "s07_code"
        experiment_py = code_dir / "experiment.py"
        if not experiment_py.exists():
            return StageResult(content="No experiment code found", exit_code=1)

        results = ""
        succeeded = False
        for attempt in range(1, 4):
            try:
                proc = subprocess.run(
                    [sys.executable, str(experiment_py)],
                    capture_output=True,
                    text=True,
                    timeout=120,
                    cwd=str(code_dir),
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                proc = None
                stderr = str(exc)
            else:
                stderr = proc.stderr

            if proc is not None and proc.returncode == 0:
                results = proc.stdout
                succeeded = True
                break

            error_type = _classify_error(stderr)
            original_code = safe_read(experiment_py)
            fix_prompt = (
                "Fix this Python experiment script.\n\n"
                f"Error type: {error_type}\n\n"
                f"Traceback/stderr:\n{stderr}\n\n"
                f"Original code:\n{original_code}\n\n"
                "Return only corrected complete Python code for experiment.py."
            )
            fix_result = run_with_fallback(
                pool=pool,
                primary="codex",
                fallback=None,
                prompt=fix_prompt,
                task_name=f"s08-fix-{ctx.slug}-{attempt}",
                timeout_primary=ctx.config.timeouts.agent_codex,
                logger=ctx.logger,
            )
            fixed_code = _extract_code(fix_result.content)
            if fixed_code:
                atomic_write(experiment_py, fixed_code)
            if attempt == 3:
                results = stderr

        atomic_write(ctx.state_dir / "s08_results.md", results)
        return StageResult(content=results, exit_code=0 if succeeded else 1)
