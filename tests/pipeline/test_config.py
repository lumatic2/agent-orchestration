from __future__ import annotations

from pipeline.config import load_config
from pipeline.models.config_schema import PipelineConfig


def test_load_default() -> None:
    config = load_config(None)
    assert isinstance(config, PipelineConfig)


def test_defaults() -> None:
    assert PipelineConfig().timeouts.agent_gemini == 180
