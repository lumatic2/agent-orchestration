# Routing Table

> Defines when to orchestrate, which agents to use, and how to route tasks.
> The orchestrator (Claude Code) references this before every task.

---

## Step -1: Check the Queue

Before evaluating any new task, scan the persistent queue:

```bash
bash ~/Desktop/agent-orchestration/scripts/orchestrate.sh --boot
```

**Priority order:**
1. **Stale dispatched** → re-dispatch with `--resume` (session crashed mid-task)
2. **Queued** → retry with `--resume` (previously rate-limited)
3. **Pending** → dispatch normally
4. **New tasks** → only after queue is empty or all items are completed

This ensures no work is lost across sessions. The queue is the source of truth for in-flight tasks.

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

## Interactive Workflow: 브레인스토밍 / 레퍼런스 리서치

브레인스토밍과 레퍼런스 리서치는 단순 위임(fire-and-forget)이 아니라,
**수집은 위임, 판단은 사용자** 패턴으로 진행한다.

```
1. [위임] Gemini에게 대량 수집 요청
   → "웹사이트 레퍼런스 20개 찾아줘", "SaaS 랜딩 트렌드 조사"

2. [보고] Claude Code가 결과를 정리하여 사용자에게 선택지 제시
   → 표, 요약, 비교 형태

3. [판단] 사용자가 방향 선택
   → "3번, 7번이 좋아", "미니멀 스타일로 가자"

4. [위임] 선택 기반으로 Gemini에게 심화 리서치 요청
   → "선택한 3개 사이트의 레이아웃 구조 분석해줘"

5. [판단] 사용자가 최종 결정

6. [위임] 결정 사항을 Codex에게 구현 위임
```

| 단계 | 누가 | 모드 |
|---|---|---|
| 자료 수집 | Gemini (위임) | 비대화형 |
| 선별/방향 결정 | 사용자 + Claude Code | 대화형 |
| 심화 리서치 | Gemini (위임) | 비대화형 |
| 최종 결정 | 사용자 | 대화형 |
| 구현 | Codex (위임) | 비대화형 |

**핵심 원칙:**
- 수집/분석은 위임 가능하지만, 방향 결정은 반드시 사용자가 한다.
- Claude Code(Opus)는 결과 요약 + 선택지 제시만 하여 토큰 절약.
- 한 번에 끝내려 하지 말고, 수집→선별→심화→결정의 반복 루프를 돈다.

## Large Document Handling

대용량 파일(50+ 페이지, 20MB+ PPT, 이미지 다수)은 Opus가 직접 읽지 않는다.

```
1. Claude Code가 파일 유형과 크기 판단
2. Gemini에게 위임: "이 문서 읽고 핵심 요약 + 구조 분석해줘"
3. Gemini가 요약본 반환 (50페이지 → 1-2페이지)
4. Claude Code(Opus)는 요약본만 읽고 판단/지시
```

| 문서 유형 | 최적 에이전트 | 이유 |
|---|---|---|
| 텍스트/PDF (50+ 페이지) | Gemini (Flash) | 1M 컨텍스트, 문서 분석 특화, 저렴 |
| 이미지/스크린샷 분석 | Claude Code → Gemini | Claude가 간단히 보고 필요시 Gemini 심화 |
| PPT/대용량 바이너리 | Gemini (Flash) | 대용량 처리에 유리 |
| 코드베이스 전체 분석 | Claude subagent (Haiku) | Glob/Grep으로 탐색, 저렴 |

**원칙: Opus는 요약본만 읽는다. 원본 분석은 항상 위임.**

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
