# Agent Orchestration

Multi-agent orchestration system. Claude Code = orchestrator, Codex + Gemini = workers.

## Quick Start

```bash
# 1. Check agent status
bash scripts/sync.sh --check

# 2. Deploy configs to all agents
bash scripts/sync.sh

# 3. Dispatch a task to Codex
bash scripts/orchestrate.sh codex "Refactor src/auth/ to use JWT"

# 4. Dispatch research to Gemini
bash scripts/orchestrate.sh gemini "Compare React vs Svelte for this project"
```

## Structure

```
agent_config.yaml       Config hub (models, flags, paths)
SHARED_PRINCIPLES.md    Behavioral rules (all agents)
ROUTING_TABLE.md        Task → agent → model mapping

adapters/
  claude_global.md      ~/CLAUDE.md source (deployed by sync.sh)
  claude.md             Orchestrator rules
  codex.md              Codex AGENTS.md (worker)
  gemini.md             Gemini GEMINI.md (worker)

scripts/                30 shell scripts
  orchestrate.sh        Dispatch tasks with fallback
  sync.sh               Deploy shared files to agent configs
  guard.sh              Safety hook (blocks destructive commands)
  *-news.sh, etc.       Cron automation (9 scripts on M4)

skills/                 24 slash commands (source of truth)
  → deployed to ~/.claude/commands/ manually

context/                Project-specific context files
pipeline/               Research pipeline (Python)
```

## Multi-Device

This repo syncs via git. Run `sync.sh` after pulling on each device.
