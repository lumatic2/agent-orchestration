from __future__ import annotations

from pathlib import Path

import yaml

from pipeline.models.config_schema import PipelineConfig


REPO_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = REPO_DIR / "pipeline" / "pipeline_config.yaml"


def load_config(path: Path | None = None) -> PipelineConfig:
    config_path = path or DEFAULT_CONFIG_PATH
    if not config_path.exists():
        return PipelineConfig()
    loaded = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    return PipelineConfig.model_validate(loaded)
