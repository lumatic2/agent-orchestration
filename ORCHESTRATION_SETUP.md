# Multi-Agent Orchestration Setup

> Give this file to Claude Code on any new machine.
> It contains everything needed to set up and operate the orchestration system.

---

## Step 1: Clone the Repo

```bash
# Install gh if needed
brew install gh          # macOS
# or: winget install GitHub.cli  # Windows

gh auth login
git clone https://github.com/Mod41529/agent-orchestration.git ~/Desktop/agent-orchestration
cd ~/Desktop/agent-orchestration
bash scripts/sync.sh
```

---

## Step 2: Verify Agents

```bash
codex --version   # OpenAI Codex CLI
gemini --version  # Google Gemini CLI
claude --version  # Claude Code
```

Install if missing:
```bash
npm install -g @openai/codex
npm install -g @google/gemini-cli
```

---

## Architecture

```
Claude Code (Opus) ─── Orchestrator: planning + judgment + delegation
    │
    ├── Codex CLI ─── Worker: code generation, refactoring, tests, debugging
    ├── Gemini CLI ─── Worker: research, document analysis, summarization
    └── Claude subagent (Haiku/Sonnet) ─── Exploration, code review
```

- **Single brain**: Claude Code owns all planning, memory, and orchestration.
- **Workers execute only**: Codex and Gemini receive task briefs, return results.
- **Shared memory**: `SHARED_MEMORY.md` in the repo — Claude Code reads/writes, workers read-only.

---

## Routing Table

| Task | Agent | Model |
|---|---|---|
| Task decomposition | Claude Code | Opus (short judgment only) |
| Codebase exploration | Claude subagent | Haiku |
| Code generation / refactoring | Codex | gpt-5.3-codex |
| Error fix iteration | Codex | gpt-5.3-codex |
| Quick / simple edits | Codex | gpt-5.3-codex-spark |
| Test execution | Codex | gpt-5.3-codex |
| Code review (diff) | Claude subagent | Sonnet |
| Research / docs | Gemini | gemini-2.5-flash |
| Deep analysis (sparingly) | Gemini | gemini-2.5-pro |
| Bulk transform | Gemini | gemini-2.5-flash-lite |

---

## How to Delegate

### To Codex
```bash
codex exec \
  --full-auto \
  --sandbox danger-full-access \
  -m gpt-5.3-codex \
  "Task description here" \
  --json
```

### To Gemini
```bash
gemini \
  --yolo \
  --sandbox \
  -m gemini-2.5-flash \
  -p "Task description here"
```

### Via orchestrate.sh (with fallback)
```bash
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh codex "task"
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh codex-spark "quick task"
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh gemini "research task"
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh gemini-pro "deep analysis"
```

---

## Task Brief Template

When delegating, always write a structured brief:

```markdown
## Goal
[One sentence — what needs to be done]

## Scope
- Files: [specific files/directories to touch]
- Read-only: [files to reference but NOT modify]

## Constraints
- [Technical constraints]
- [What NOT to do]

## Done Criteria
- [ ] [Verifiable condition, e.g., "npm test passes"]
```

---

## Token Discipline

### Plans (user subscriptions)
- **Claude**: Max 20x ($200/mo) — 5h rolling window, Opus ~180/window, Sonnet ~900/window
- **ChatGPT/Codex**: Pro ($200/mo) — most generous limits, use for heavy work
- **Gemini**: Pro ($20/mo) — 1,500 req/day, Flash 300 prompts/day, Pro 100/day

### Rules
1. **Opus is for judgment only.** 3-5 lines per turn. Never read large files with Opus.
2. **Use Haiku subagents** for file exploration (1/3 cost of Sonnet).
3. **Push all heavy code work to Codex** (most generous quota).
4. **Gemini = Flash by default.** Pro model max 10x/day.
5. **Break long conversations.** Save state to SHARED_MEMORY.md, start fresh.

### Fallback Chain (when rate-limited)
```
Code tasks:    Codex → Claude (Sonnet) → Gemini (Flash)
Research:      Gemini (Flash) → Claude (Haiku) → Codex
Orchestration: Claude (Opus) → Claude (Sonnet) → PAUSE
```

---

## Permissions

| Agent | Mode | Flag |
|---|---|---|
| Claude Code | Auto-approve + safety hooks | `--dangerously-skip-permissions` |
| Codex | Full auto + full access | `--full-auto --sandbox danger-full-access` |
| Gemini | YOLO + sandbox | `--yolo --sandbox` |

Safety hook (`guard.sh`) blocks: `rm -rf /`, `git push --force`, `.env` access, destructive SQL.

---

## Sync Across Devices

After any changes to shared files:
```bash
cd ~/Desktop/agent-orchestration
git add -A && git commit -m "Update shared memory" && git push
```

On the other device:
```bash
cd ~/Desktop/agent-orchestration
git pull && bash scripts/sync.sh
```

---

## Config Updates

When agent CLIs update (new model names, changed flags), edit **only** `agent_config.yaml`:
```yaml
models:
  codex:
    heavy: "gpt-5.3-codex"      # ← change here when models update
    light: "gpt-5.3-codex-spark"
  gemini:
    default: "gemini-2.5-flash"
  claude:
    heavy: "opus"
    mid: "sonnet"
    light: "haiku"
```

Then run `bash scripts/sync.sh` to redeploy.
