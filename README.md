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
SHARED_MEMORY.md        Cross-session memory (orchestrator manages)
ROUTING_TABLE.md        Task → agent → model mapping

adapters/
  claude.md             Claude Code orchestrator instructions
  codex.md              Codex AGENTS.md (worker)
  gemini.md             Gemini GEMINI.md (worker)

scripts/
  sync.sh               Deploy shared files to agent configs
  orchestrate.sh         Dispatch tasks with fallback
  guard.sh               Safety hook (blocks destructive commands)
  memory_compact.sh      Prevent memory bloat

templates/
  task_brief.md          Standard task delegation format
```

## Multi-Device

This repo syncs via git. Run `sync.sh` after pulling on each device.
