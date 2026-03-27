from __future__ import annotations

from pydantic import BaseModel, Field


class TimeoutConfig(BaseModel):
    agent_gemini: int = Field(default=180)
    agent_codex: int = Field(default=300)
    agent_chatgpt: int = Field(default=300)
    agent_claude: int = Field(default=180)
    watchdog_stale_minutes: int = Field(default=10)


class ThresholdConfig(BaseModel):
    s04_min_output_bytes: int = Field(default=500)
    s14_unverified_rate_gate: int = Field(default=50)
    max_refine: int = Field(default=3)
    max_pivot: int = Field(default=2)
    payload_truncate: int = Field(default=8000)
    payload_truncate_s11: int = Field(default=20000)


class ApiConfig(BaseModel):
    arxiv_max: int = Field(default=15)
    ss_max: int = Field(default=10)
    openalex_max: int = Field(default=10)
    pubmed_max: int = Field(default=15)


class AgentRouting(BaseModel):
    primary: str
    fallback: str | None = Field(default=None)


class AgentConfig(BaseModel):
    s02_keywords: AgentRouting = Field(
        default_factory=lambda: AgentRouting(primary="gemini", fallback="codex")
    )
    s04: AgentRouting = Field(default_factory=lambda: AgentRouting(primary="codex", fallback="claude"))
    s05: AgentRouting = Field(default_factory=lambda: AgentRouting(primary="codex", fallback="chatgpt"))
    s10: AgentRouting = Field(default_factory=lambda: AgentRouting(primary="codex", fallback="claude"))
    s11: AgentRouting = Field(default_factory=lambda: AgentRouting(primary="codex", fallback="chatgpt"))
    s14: AgentRouting = Field(default_factory=lambda: AgentRouting(primary="codex", fallback="claude"))
    s15_reviewers: list[str] = Field(default_factory=lambda: ["codex", "gemini", "claude"])


class VaultConfig(BaseModel):
    ssh_host: str = Field(default="m4")
    ssh_timeout: int = Field(default=10)
    base_path: str = Field(default="~/vault/30-projects/papers")


class TemplateConfig(BaseModel):
    typst_dir: str = Field(default="templates/typst")
    prompts_dir: str = Field(default="templates/prompts")
    default: str = Field(default="A")


class PipelineConfig(BaseModel):
    timeouts: TimeoutConfig = Field(default_factory=TimeoutConfig)
    thresholds: ThresholdConfig = Field(default_factory=ThresholdConfig)
    api: ApiConfig = Field(default_factory=ApiConfig)
    agents: AgentConfig = Field(default_factory=AgentConfig)
    vault: VaultConfig = Field(default_factory=VaultConfig)
    templates: TemplateConfig = Field(default_factory=TemplateConfig)
