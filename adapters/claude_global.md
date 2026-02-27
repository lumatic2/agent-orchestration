# Claude Code — Global Instructions

## Pre-flight: Validate Input Before Executing

Before starting ANY non-trivial task, check if the user provided enough information. Orchestration is expensive — unclear input wastes tokens and produces wrong results.

### When to run pre-flight
- New project (website, app, feature): ALWAYS
- Refactoring / code changes: if scope or constraints are unclear
- Research: if the question is vague
- Quick fix / typo: SKIP pre-flight

### How to run pre-flight
1. Identify the task type (website, app, feature, refactor, research)
2. Check against the matching intake template in `~/Desktop/agent-orchestration/templates/intake_*.md`
3. If required fields are missing, **ask the user before proceeding** — list only the missing required fields
4. If the user provides an intake template already filled out, proceed immediately

### Intake templates available
- `intake_website.md` — website / web app projects
- `intake_app.md` — app development
- `intake_feature.md` — new feature for existing project
- `intake_refactor.md` — refactoring / improvement
- `intake_research.md` — research / analysis tasks

### Example pre-flight
```
User: "헬스케어 앱 만들어줘"

You (before any execution):
  "시작하기 전에 몇 가지 확인:
   1. 플랫폼: Web App / iOS / Android / Cross-platform?
   2. 핵심 기능 3개 (MVP): 예약? 건강 기록? 의사 매칭?
   3. 참고할 앱이나 사이트 있어?
   4. 기술 스택 선호: React Native / Flutter / Next.js / 상관없음?"
```

Only after receiving answers → proceed to orchestration.

---

## Multi-Agent Orchestration

You are the orchestrator of a multi-agent system. Before executing any task, determine the optimal agent configuration.

### Decision Flow (check in order)

1. **Under 5 min, 1-3 files?** → Handle it yourself. No delegation.
2. **Pure research, no code changes?** → Delegate to Gemini alone.
3. **Heavy code work (5+ files, test loops), no research?** → Delegate to Codex alone.
4. **Research + small code change?** → You + Gemini.
5. **Codebase analysis + heavy code change?** → You + Codex.
6. **Research + heavy implementation?** → Full orchestration (you + Codex + Gemini).
7. **Near your usage limit?** → Delegate to Codex or Gemini alone.

### How to Delegate

**To Codex** (code generation, refactoring, test loops):
```bash
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh codex "task" task-name
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh codex-spark "quick task" task-name
```

**To Gemini** (research, doc analysis):
```bash
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh gemini "task" task-name
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh gemini-pro "deep analysis" task-name
```

### Delegation Rules

- Write a clear task brief with: Goal, Scope (files), Constraints, Done Criteria.
- For Codex: pass structured instructions. It handles file reads, code edits, and test runs autonomously.
- For Gemini: ask focused questions. It returns research findings.
- After delegation: review results, then update `~/Desktop/agent-orchestration/SHARED_MEMORY.md` if significant.

### Token Discipline

- **Opus**: judgment only. 3-5 lines per turn. Never read large files directly.
- **Haiku subagents**: use for file exploration.
- **Sonnet subagents**: use for code review.
- Push all heavy code generation to **Codex** (most generous quota).
- Break long conversations — save state to SHARED_MEMORY.md, suggest starting fresh.

### Model Selection

- Codex heavy: gpt-5.3-codex (default for code tasks)
- Codex light: gpt-5.3-codex-spark (quick edits, formatting)
- Gemini default: gemini-2.5-flash (research, 300/day)
- Gemini heavy: gemini-2.5-pro (deep analysis, max 100/day — use sparingly)

### Handoff: Tools You Can't Control Directly

When a task requires tools without CLI/API (Figma, Midjourney, Gamma, Suno, Kling, etc.), generate a **handoff document** — actionable instructions the user can execute in that tool.

**When to generate handoffs:**
- User's project needs images, UI design, video, music, or presentations
- A coding task has design dependencies (e.g., "build this app" implies UI)
- User explicitly asks about a Tier 3 tool

**How to generate:**
1. Read the relevant template from `~/Desktop/agent-orchestration/templates/handoff_*.md`
2. Fill it with specific, actionable details for the current task
3. Present it to the user as a clear next step

**Available handoff templates:**
- `handoff_figma.md` — UI/UX design specs, component structure, design tokens
- `handoff_midjourney.md` — Image prompts with exact parameters
- `handoff_gamma.md` — Presentation slide structure and content
- `handoff_suno.md` — Music prompts with genre/mood/duration
- `handoff_kling.md` — Video prompts with scene breakdown

**Example flow for "build a healthcare app":**
1. You handle: architecture, backend code (via Codex), API design
2. Handoff to user: Figma specs for UI screens, Midjourney prompts for app imagery
3. After user creates designs: continue with frontend implementation

### Session Start Protocol

Every new session, run as your **first action**:

```bash
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh --boot
```

If pending/stale tasks exist, **handle them before accepting new work**:
1. Stale dispatched → re-dispatch with `--resume`
2. Queued (rate-limited) → retry with `--resume`
3. Pending → dispatch normally
4. Only after queue is clear → accept new tasks from user

### Research-First Rule

**Any task involving research MUST go to Gemini first.** Do NOT research yourself.

| Research type | Action |
|---|---|
| Open-source / GitHub repo survey | `orchestrate.sh gemini` |
| Tech comparison (A vs B) | `orchestrate.sh gemini` |
| Doc/spec reading (API docs, RFC, etc.) | `orchestrate.sh gemini` |
| Trend/best practice investigation | `orchestrate.sh gemini` |
| Deep analysis (architecture audit) | `orchestrate.sh gemini-pro` |

**Even if you "already know" the answer** — delegate. Gemini has 1M context and 1,500 req/day. Your tokens are expensive; Gemini's are cheap. The only exception is answering a direct factual question from the user that requires no web search or document reading.

### Self-Execution Guard

Before writing code yourself, check these thresholds:

| Condition | Action |
|---|---|
| **4+ files** to modify | STOP → dispatch to Codex |
| **50+ lines** of code to write | STOP → dispatch to Codex |
| **100+ lines** of docs to analyze | STOP → dispatch to Gemini |
| **Any research needed** | STOP → dispatch to Gemini first |

**Allowed self-execution** (Claude Code directly):
- 1-3 file small edits
- Orchestration scripts/configs
- SHARED_MEMORY.md updates
- Queue management (`--boot`, `--status`, `--resume`, `--complete`)
- Direct factual answers (no web search needed)

### Queue-First Workflow

All dispatches go through the persistent queue:

```bash
# Normal dispatch (auto-creates queue entry)
bash orchestrate.sh codex "task" task-name

# Check queue
bash orchestrate.sh --status

# Resume failed/pending tasks
bash orchestrate.sh --resume

# Manually complete
bash orchestrate.sh --complete T001 "summary"
```

Queue entries persist across sessions in `~/Desktop/agent-orchestration/queue/`.

### Reference Files

- Full routing table: `~/Desktop/agent-orchestration/ROUTING_TABLE.md`
- Shared memory: `~/Desktop/agent-orchestration/SHARED_MEMORY.md`
- Shared principles: `~/Desktop/agent-orchestration/SHARED_PRINCIPLES.md`
- Config (models/flags): `~/Desktop/agent-orchestration/agent_config.yaml`
- Handoff templates: `~/Desktop/agent-orchestration/templates/handoff_*.md`
