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

## MCP Servers (방향 2)

Codex CLI와 Gemini CLI를 MCP 서버로 래핑해서 Claude Code / Cursor / Windsurf 등 모든 MCP 클라이언트에서 "에이전트를 도구로" 호출할 수 있게 만든 프로토타입.

```bash
claude mcp add codex-mcp  -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
claude mcp add gemini-mcp -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

등록 후 재시작하면 `mcp__codex-mcp__codex_task` / `mcp__gemini-mcp__gemini_task` 형태로 노출된다.

- 구현: [`mcp-servers/`](./mcp-servers/)
- 아키텍처·도구 스키마·후속 개선: [`docs/mcp-servers.md`](./docs/mcp-servers.md)
- 기존 `codex:rescue` / `gemini:rescue` Skill 플러그인과 공존 (동일 companion job store 공유)

## Roadmap

- **OpenClaw integration** — browser automation agent, currently maintained as a separate project. Planned integration as an MCP tool once stable.

## Multi-Device

This repo syncs via git. Run `sync.sh` after pulling on each device.
