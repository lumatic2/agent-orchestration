# Claude Code — Global Instructions

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

### Reference Files

- Full routing table: `~/Desktop/agent-orchestration/ROUTING_TABLE.md`
- Shared memory: `~/Desktop/agent-orchestration/SHARED_MEMORY.md`
- Shared principles: `~/Desktop/agent-orchestration/SHARED_PRINCIPLES.md`
- Config (models/flags): `~/Desktop/agent-orchestration/agent_config.yaml`
- Handoff templates: `~/Desktop/agent-orchestration/templates/handoff_*.md`
