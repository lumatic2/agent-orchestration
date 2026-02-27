# Routing Table

> Defines when to orchestrate, which agents to use, and how to route tasks.
> The orchestrator (Claude Code) references this before every task.

---

## Step 0: Do I Need Orchestration?

Before delegating, ask these questions in order:

```
1. Can this be done in under 5 minutes with 1-3 files?
   → YES: Claude Code alone. Stop here.

2. Is this purely research / document analysis, no code changes?
   → YES: Gemini alone. Stop here.

3. Is this heavy code work (5+ files, test loops, scaffolding)
   with no research needed?
   → YES: Codex alone. Stop here.

4. Does this need research AND code changes?
   → Research is small + code is small: Claude + Gemini
   → Research is small + code is heavy: Claude + Codex
   → Research is deep + code is heavy: Full orchestration

5. Am I near Claude usage limits?
   → YES: Send to Codex alone or Gemini alone.
```

## Decision Matrix

| Task Characteristics | Agent Config | Example |
|---|---|---|
| Single line fix, typo, config change | **Claude alone** | Fix import path |
| Write one function, small edit | **Claude alone** | Add validation to form |
| Code review (small diff) | **Claude alone** | Review a PR with 3 files |
| Data analysis, Notion operations | **Claude alone** | Analyze CSV, update Notion |
| Tech research, doc summary | **Gemini alone** | Compare React vs Svelte |
| API doc analysis, long doc reading | **Gemini alone** | Summarize 50-page spec |
| Large refactor (5+ files) | **Codex alone** | Refactor auth module |
| New project scaffolding | **Codex alone** | Create Next.js boilerplate |
| Error fix loop (test→fix→repeat) | **Codex alone** | Fix failing CI pipeline |
| Research then apply to code (small) | **Claude + Gemini** | Best practice → update config |
| Analyze codebase then modify (heavy) | **Claude + Codex** | Audit → refactor pattern |
| Research + large implementation | **Full orchestration** | Evaluate lib → build feature |
| Multiple projects in parallel | **Full orchestration** | Frontend + backend simultaneously |

## Task → Agent → Model (when orchestrating)

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
