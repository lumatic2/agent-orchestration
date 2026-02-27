# Routing Table

> Defines which agent + model handles each task type.
> The orchestrator (Claude Code) references this to delegate work.

---

## Task → Agent → Model

| Task Type | Agent | Model | Reason |
|---|---|---|---|
| **Task decomposition** | Claude Code | Opus | Complex reasoning, short output |
| **Final integration** | Claude Code | Opus | Judgment call, short output |
| **Codebase exploration** | Claude subagent | Haiku | Cheap, Read/Grep/Glob only |
| **File classification** | Claude subagent | Haiku | Simple pattern matching |
| **Code generation** | Codex | gpt-5.3-codex | Most generous limits |
| **Code refactoring** | Codex | gpt-5.3-codex | Heavy token use → Codex |
| **Error fix iteration** | Codex | gpt-5.3-codex | Retry loops burn tokens |
| **Test execution** | Codex | gpt-5.3-codex | May need many retries |
| **Quick edits** | Codex | codex-spark | 15x faster, saves quota |
| **Boilerplate** | Codex | codex-spark | Simple generation |
| **Code review (diff)** | Claude subagent | Sonnet | Quality judgment on small diff |
| **Research / docs** | Gemini | 2.5 Flash | 1M context, cheap |
| **Deep analysis** | Gemini | 2.5 Pro | Max 100/day, use sparingly |
| **Bulk transform** | Gemini | 2.5 Flash-Lite | Lowest cost |
| **Data analysis** | Claude Code | Sonnet | Direct execution |
| **Notion operations** | Claude Code | Sonnet | Has MCP/script access |

## Fallback Rules

When an agent hits rate limits:

```
Code tasks:    Codex → Claude (Sonnet) → Gemini (Flash)
Research:      Gemini (Flash) → Claude (Haiku) → Codex
Orchestration: Claude (Opus) → Claude (Sonnet) → PAUSE
```

## Scope Isolation

To prevent file conflicts during parallel execution:

- Assign each worker a **non-overlapping directory** or file set.
- If overlap is unavoidable, run workers **sequentially**, not in parallel.
- The orchestrator must verify no scope overlap before dispatching parallel tasks.
