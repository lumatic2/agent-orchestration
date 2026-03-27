from __future__ import annotations

import argparse
import re
from pathlib import Path

from pipeline.core.checkpoint import CheckpointManager
from pipeline.core.cleanup import install_handlers
from pipeline.core.decision import DecisionHandler
from pipeline.core.gate import GateManager
from pipeline.core.logging import PipelineLogger
from pipeline.core.platform import is_windows
from pipeline.core.watchdog import WatchdogChecker
from pipeline.models.config_schema import PipelineConfig
from pipeline.models.pipeline_state import PipelineState, StageStatus
from pipeline.models.stage_result import StageResult
from pipeline.stages.base import Stage, StageContext


def slugify(text: str) -> str:
    # Keep Korean (가-힣), alphanumeric, replace rest with dashes
    slug = re.sub(r"[^a-z0-9가-힣]+", "-", text.strip().lower())
    slug = re.sub(r"-{2,}", "-", slug).strip("-")
    # Truncate to 60 chars at word boundary
    if len(slug) > 60:
        slug = slug[:60].rsplit("-", 1)[0]
    return slug or "topic"


class PipelineRunner:
    def __init__(self, config: PipelineConfig, args: argparse.Namespace) -> None:
        self.config = config
        self.args = args
        self.repo_dir = Path(__file__).resolve().parent.parent
        self.slug = slugify(args.topic)
        self.vault_dir = (
            Path(args.vault_dir)
            if args.vault_dir
            else (Path.home() / "Desktop" / "research" if is_windows() else Path.home() / "vault")
        )
        self.paper_dir = self.vault_dir / "30-projects" / "papers" / self.slug
        self.state_dir = self.paper_dir / "state"
        self.pipeline_file = self.paper_dir / "pipeline.json"
        self.log_dir = self.repo_dir / "logs"

        self.paper_dir.mkdir(parents=True, exist_ok=True)
        self.state_dir.mkdir(exist_ok=True)
        self.log_dir.mkdir(exist_ok=True)

        self.logger = PipelineLogger(self.log_dir, json_mode=args.log_json)
        self.checkpoint = CheckpointManager(self.pipeline_file)
        self.gate = GateManager(self.checkpoint, self.logger)
        self.decision_handler = DecisionHandler(config, self.checkpoint, self.logger)
        self.watchdog = WatchdogChecker(config, self.logger)

    def _build_stages(self) -> list[Stage]:
        from pipeline.stages.s01_scope import S01Scope
        from pipeline.stages.s02_literature import S02Literature
        from pipeline.stages.s03_screening import S03Screening
        from pipeline.stages.s04_extraction import S04Extraction
        from pipeline.stages.s05_synthesis import S05Synthesis
        from pipeline.stages.s06_experiment import S06Experiment
        from pipeline.stages.s07_code_gen import S07CodeGen
        from pipeline.stages.s08_experiment_run import S08ExperimentRun
        from pipeline.stages.s09_decision import S09Decision
        from pipeline.stages.s10_draft import S10Draft
        from pipeline.stages.s11_peer_review import S11PeerReview
        from pipeline.stages.s12_quality_gate import S12QualityGate
        from pipeline.stages.s13_archive import S13Archive
        from pipeline.stages.s14_citation import S14CitationVerify
        from pipeline.stages.s16_pdf import S16Pdf

        try:
            from pipeline.stages.s15_validation import S15Validation
            stage_15_cls: type[Stage] = S15Validation
        except ImportError:
            class S15ValidationFallback(Stage):
                @property
                def name(self) -> str:
                    return "S15"

                @property
                def description(self) -> str:
                    return "Validation"

                def should_skip(self, ctx: StageContext) -> bool:
                    del ctx
                    return True

                def run(self, ctx: StageContext) -> StageResult:
                    del ctx
                    return StageResult(content="S15Validation is unavailable")

            stage_15_cls = S15ValidationFallback

        return [
            S01Scope(),
            S02Literature(),
            S03Screening(),
            S04Extraction(),
            S05Synthesis(),
            S06Experiment(),
            S07CodeGen(),
            S08ExperimentRun(),
            S09Decision(),
            S10Draft(),
            S11PeerReview(),
            S12QualityGate(),
            S13Archive(),
            S14CitationVerify(),
            stage_15_cls(),
            S16Pdf(),
        ]

    def run(self) -> int:
        state = self.checkpoint.load()
        if not state.topic:
            state = PipelineState(
                topic=self.args.topic,
                slug=self.slug,
                skip_experiment=self.args.skip_experiment,
            )

        install_handlers(state, self.pipeline_file)

        stale = self.watchdog.check(state, skip_stage=self.args.approve_gate)
        for stage_name in stale:
            self.checkpoint.stage_fail(state, stage_name)

        if self.args.approve_gate and self.gate.is_gate_approved(
            state, self.args.approve_gate, self.args.approve_gate
        ):
            self.checkpoint.stage_complete(state, self.args.approve_gate)

        if self.args.decide:
            _, next_stage = self.decision_handler.handle(state, self.args.decide)
            state.current_stage = next_stage
            self.checkpoint.save(state)

        stages = self._build_stages()

        start = self.checkpoint.get_resume_stage(state)
        ctx = StageContext(
            topic=self.args.topic,
            slug=self.slug,
            state_dir=self.state_dir,
            paper_dir=self.paper_dir,
            config=self.config,
            logger=self.logger,
            skip_experiment=self.args.skip_experiment,
        )

        for stage in stages[start - 1 :]:
            stage_info = state.stages.get(stage.name)
            if stage_info and stage_info.status == StageStatus.completed:
                continue

            if stage.should_skip(ctx):
                self.checkpoint.stage_skip(state, stage.name)
                continue

            if self.args.dry_run:
                self.logger.info(f"[DRY-RUN] Would run {stage.name}: {stage.description}")
                continue

            if self.args.stage and stage.name != self.args.stage:
                continue

            self.logger.stage_start(stage.name, stage.description)
            self.checkpoint.stage_start(state, stage.name)

            try:
                result = stage.run(ctx)
                if result.gate_required:
                    if not self.gate.is_gate_approved(state, stage.name, self.args.approve_gate):
                        state.gate_pending_stage = stage.name
                        self.checkpoint.save(state)
                        self.logger.info(f"Gate pending: {stage.name}. Re-run with --approve-gate {stage.name}")
                        return 42
                if result.decision_required:
                    self.decision_handler.set_pending(state)
                    self.checkpoint.save(state)
                    self.logger.info(
                        f"Decision pending: {stage.name}. Re-run with --decide PROCEED|REFINE|PIVOT"
                    )
                    return 42
                self.checkpoint.stage_complete(state, stage.name)
            except Exception as exc:
                self.logger.error(f"{stage.name} failed: {exc}")
                self.checkpoint.stage_fail(state, stage.name)
                return 1

        self.logger.info("Pipeline completed successfully")
        return 0
