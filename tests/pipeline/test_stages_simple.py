from __future__ import annotations

from pipeline.models.config_schema import PipelineConfig
from pipeline.stages.base import StageContext
from pipeline.stages.s01_scope import S01Scope
from pipeline.stages.s03_screening import S03Screening
from pipeline.stages.s06_experiment import S06Experiment
from pipeline.stages.s12_quality_gate import S12QualityGate


def _ctx(tmp_path) -> StageContext:
    state_dir = tmp_path / "state"
    paper_dir = tmp_path / "paper"
    state_dir.mkdir(parents=True, exist_ok=True)
    paper_dir.mkdir(parents=True, exist_ok=True)
    return StageContext(
        topic="test",
        slug="test",
        state_dir=state_dir,
        paper_dir=paper_dir,
        config=PipelineConfig(),
        logger=None,
    )


def test_s01_creates_scope(tmp_path) -> None:
    ctx = _ctx(tmp_path)
    S01Scope().run(ctx)
    out = (ctx.state_dir / "s01_scope.md").read_text(encoding="utf-8")
    assert "test" in out


def test_s03_creates_screening(tmp_path) -> None:
    ctx = _ctx(tmp_path)
    S03Screening().run(ctx)
    assert (ctx.state_dir / "s03_screened.md").exists()


def test_s06_creates_experiment(tmp_path) -> None:
    ctx = _ctx(tmp_path)
    result = S06Experiment().run(ctx)
    assert (ctx.state_dir / "s06_experiment.md").exists()
    assert result.gate_required is True


def test_s06_skip(tmp_path) -> None:
    ctx = _ctx(tmp_path)
    ctx.skip_experiment = True
    assert S06Experiment().should_skip(ctx) is True


def test_s12_creates_quality(tmp_path) -> None:
    ctx = _ctx(tmp_path)
    (ctx.state_dir / "s11_revised.md").write_text("dummy revised", encoding="utf-8")
    result = S12QualityGate().run(ctx)
    assert (ctx.state_dir / "s12_quality.md").exists()
    assert result.gate_required is True
