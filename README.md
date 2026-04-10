# Agent Orchestration

Multi-agent orchestration system. Claude Code = orchestrator, Codex + Gemini = workers.

## How It Works

```
User → Claude Code (orchestrator)
           ├── Codex    — implementation, refactoring, code review
           └── Gemini   — research, web search, long-context analysis
```

Tasks are decomposed, routed by complexity and domain, delegated to the right worker, and cross-reviewed before returning results.

## Quick Start

```bash
# Check that all agent configs are in sync
bash scripts/sync.sh --check

# Deploy shared config to all agents
bash scripts/sync.sh
```

Workers are called via MCP tools (`mcp__codex-mcp__codex_task`, `mcp__gemini-mcp__gemini_task`) or the built-in Skill system from Claude Code.

## Structure

```
agent_config.yaml       Model tiers, routing flags, complexity thresholds
SHARED_PRINCIPLES.md    Behavioral rules shared across all agents
ROUTING_TABLE.md        Task → agent → model decision table

adapters/
  claude_global.md      ~/CLAUDE.md source (deployed by sync.sh)
  claude.md             Orchestrator rules
  codex.md              Codex worker config (AGENTS.md)
  gemini.md             Gemini worker config

mcp-servers/
  codex-mcp/            MCP server wrapping Codex CLI
  gemini-mcp/           MCP server wrapping Gemini CLI

scripts/
  sync.sh               Deploy shared config to all agents
  guard.sh              Safety hook (blocks destructive commands)
  env.sh                Cross-platform path setup

examples/
  adversarial-review-template.md   Multi-agent review pattern
  deep-research-template.md        Long-form research pipeline
  prompts/                         Reusable prompt templates
```

## MCP Servers

Codex CLI and Gemini CLI wrapped as MCP servers — callable as tools from Claude Code, Cursor, or any MCP client.

```bash
# Register (adjust path to your local clone)
claude mcp add codex-mcp -- node /path/to/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
claude mcp add gemini-mcp -- node /path/to/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

After restart, tools are exposed as `mcp__codex-mcp__codex_task` / `mcp__gemini-mcp__gemini_task`.

- Implementation: [`mcp-servers/`](./mcp-servers/)
- Architecture and tool schema: [`docs/mcp-servers.md`](./docs/mcp-servers.md)

## Routing

See [`ROUTING_TABLE.md`](./ROUTING_TABLE.md) for the full task → agent → model decision table.

Key rules:
- Codex for anything that writes or modifies files
- Gemini for research, web search, documents longer than context window
- Claude stays as orchestrator — delegates, reviews, decides

## Roadmap

- **OpenClaw integration** — browser automation agent, planned as an MCP tool once stable.

## Multi-Device

Syncs via git. Run `bash scripts/sync.sh` after pulling on each device.
