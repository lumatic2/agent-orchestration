# Task: agent-orchestration-Codex_main 신규 repo 구축

## Goal
현재 `agent-orchestration` repo를 Codex CLI가 오케스트레이터인 구조로 재구축한다.
새 GitHub repo `agent-orchestration-Codex_main`을 생성하고, 파일을 마이그레이션한다.

## Background
- 기존 오케스트레이터: Claude Code (claude CLI)
- 새 오케스트레이터: Codex CLI (codex interactive mode)
- 기존 워커: codex exec (코딩), gemini (리서치) → 그대로 유지
- 병행 운영: 기존 repo는 유지, 새 repo는 독립적으로 구축

## Step 1: 새 repo 생성 및 기본 구조 복사

```bash
cd ~/projects
git clone https://github.com/Mod41529/agent-orchestration agent-orchestration-Codex_main
cd agent-orchestration-Codex_main
git remote set-url origin https://github.com/Mod41529/agent-orchestration-Codex_main
gh repo create agent-orchestration-Codex_main --private --source=. --remote=origin --push
```

또는 fresh init:
```bash
mkdir ~/projects/agent-orchestration-Codex_main
cd ~/projects/agent-orchestration-Codex_main
git init
gh repo create Mod41529/agent-orchestration-Codex_main --private --source=. --remote=origin
```

## Step 2: 재사용 파일 복사

아래 항목을 `~/projects/agent-orchestration/`에서 그대로 복사:
- `scripts/orchestrate.sh`
- `agent_config.yaml`
- `SHARED_MEMORY.md`
- `SHARED_PRINCIPLES.md`
- `templates/` (전체)
- `context/` (전체)
- `queue/` (디렉토리만, 내용 없이)
- `logs/` (디렉토리만)

## Step 3: AGENTS.md 작성 (핵심 작업)

`~/projects/agent-orchestration/CLAUDE.md` 와
`~/projects/agent-orchestration/ROUTING_TABLE.md` 를 읽고,
Codex CLI용 `AGENTS.md`로 통합 마이그레이션한다.

### 마이그레이션 규칙

**제거할 것:**
- Claude Code 전용 항목 (Plan Mode, Extended Thinking, subagent types: Explore/Plan/general-purpose)
- `EnterPlanMode`, `ExitPlanMode` 같은 Claude Code tool 참조
- "현재 모델이 부적절하면 안내" 같은 Claude Code UI 관련 내용
- Skill tool 관련 내용

**유지할 것:**
- Self-Execution Guard 임계값 (50줄/4파일)
- Decision Flow (오케스트레이션 판단 로직)
- orchestrate.sh 호출 방식 (그대로)
- Gemini/Codex 위임 규칙
- Queue-First Workflow
- Research-First Rule
- Domain-Specific Routing 표
- Token Discipline
- Pre-flight (intake templates)
- Knowledge Vault 규칙
- Session Start Protocol (--boot)

**변경할 것:**
- "Claude Code" → "Codex" (오케스트레이터 주체 변경)
- FIRST ACTION 블록: `orchestrate.sh --boot` 실행 지시는 유지
- 모델 가이드: Sonnet/Opus → gpt-5.3-codex / gpt-5.4 등 Codex 모델로 대체
- MCP 설명: Codex MCP 설정 방식으로 업데이트 (MCP는 동일하게 사용 가능)
- "Plan mode 실행 추천 블록" → Codex에 맞는 간단한 effort 가이드로 교체

### AGENTS.md 최상단 구조
```
# Codex Orchestration — Global Instructions
## 기본 규칙
## FIRST ACTION (Every Session)
## Pre-flight
## Self-Execution Guard
## Multi-Agent Orchestration (Decision Flow)
## orchestrate.sh 사용법
## Domain-Specific Routing
## Queue-First Workflow
## Knowledge Vault
## Session End
```

## Step 4: README.md 작성

간단하게:
- 이 repo가 무엇인지
- 오케스트레이터: Codex CLI
- 워커: codex exec (코딩), gemini (리서치)
- 시작 방법: `codex` → AGENTS.md 자동 로드 → `bash scripts/orchestrate.sh --boot`

## Step 5: 초기 커밋 및 push

```bash
git add .
git commit -m "init: Codex-main orchestration repo"
git push -u origin main
```

## Done Criteria
- [ ] GitHub repo `agent-orchestration-Codex_main` 생성 완료 (private)
- [ ] 재사용 파일 복사 완료
- [ ] AGENTS.md 작성 완료 (Claude Code 전용 내용 없음)
- [ ] README.md 작성 완료
- [ ] 초기 커밋 push 완료
- [ ] `codex` 실행 시 AGENTS.md 자동 로드 확인 가능한 상태

## Constraints
- 기존 `agent-orchestration` repo 수정 금지
- GitHub username: Mod41529
- Local path: `~/projects/agent-orchestration-Codex_main`
- Private repo
