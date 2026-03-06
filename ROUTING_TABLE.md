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
1. Does this task involve ANY research?
   (open-source survey, tech comparison, doc reading, trend analysis)
   → YES: Gemini FIRST. Always. Then proceed to step 2 with findings.

2. Can this be done in under 5 minutes with 1-3 files?
   → YES: Claude Code alone. Stop here.

3. Is this purely research / document analysis, no code changes?
   → YES: Gemini alone. Stop here.

4. Is this heavy code work (5+ files, test loops, scaffolding)
   with no research needed?
   → YES: Codex alone. Stop here.

5. Does this need research AND code changes?
   → Research is small + code is small: Claude + Gemini
   → Research is small + code is heavy: Claude + Codex
   → Research is deep + code is heavy: Full orchestration

6. Am I near Claude usage limits?
   → YES: Send to Codex alone or Gemini alone.
```

> **Rule: Claude Code never researches.** If a task has a research component,
> dispatch to Gemini before doing anything else. Gemini returns findings,
> then Claude decides and routes the implementation.

## Decision Matrix

| Task Characteristics | Agent Config | Example |
|---|---|---|
| Single line fix, typo, config change | **Claude alone** | Fix import path |
| Write one function, small edit | **Claude alone** | Add validation to form |
| Code review (small diff) | **Claude alone** | Review a PR with 3 files |
| Data analysis | **Claude alone** | Analyze CSV |
| Notion: 조사+콘텐츠 생성+저장 | **Gemini alone** | 가이드북 작성 → Notion 직접 저장 |
| Notion: DB 스키마 설계, 복잡한 편집 | **Claude alone** | DB 구조 설계, 판단 필요 작업 |
| Tech research, doc summary | **Gemini alone** | Compare React vs Svelte |
| API doc analysis, long doc reading | **Gemini alone** | Summarize 50-page spec |
| Large refactor (5+ files) | **Codex alone** | Refactor auth module |
| New project scaffolding | **Codex alone** | Create Next.js boilerplate |
| Error fix loop (test→fix→repeat) | **Codex alone** | Fix failing CI pipeline |
| Research then apply to code (small) | **Claude + Gemini** | Best practice → update config |
| Analyze codebase then modify (heavy) | **Claude + Codex** | Audit → refactor pattern |
| Research + large implementation | **Full orchestration** | Evaluate lib → build feature |
| Multiple projects in parallel | **Full orchestration** | Frontend + backend simultaneously |

## Domain-Specific Routing

| 작업 도메인 | 주 에이전트 | 보조 | 이유 |
|---|---|---|---|
| Google 생태계 (YouTube, Drive, Docs) | Gemini | Claude(정리) | Google API 네이티브, 1M 컨텍스트, 영상 자막 분석 |
| 미디어 분석 (이미지/영상/오디오) | Gemini | Codex(구현) | 멀티모달 입력 처리 → 분석 결과로 코드 생성 |
| 데이터 파이프라인 (CSV, DB, 시각화) | Claude(소규모) / Codex(대규모) | Gemini(분석) | 스크립트 크기에 따라 분기 |
| Notion 조사+작성 파이프라인 | Gemini(MCP 직접) | Claude(검토) | Gemini가 조사→Notion 원스톱, 토큰 절약 |
| Notion DB 설계·복잡한 구조 | Claude(MCP) | — | DDL·판단 필요, Claude MCP가 기능 완전 |
| Notion 순수 저장 (AI 불필요) | notion_db.py | — | 비용 0, bash 직접 호출 |
| Slack 연동 | Claude(MCP 보유) | — | Slack MCP는 Claude만 |
| 번역/현지화 | Codex CLI/gpt-5(대량) | Gemini(검색 필요 시) | ChatGPT Pro 쿼터 활용, 검색 불필요 |
| CI/CD, DevOps | Codex(파이프라인) | Gemini(에러 분석) | 에러 로그 분석 = 리서치 |
| **세무/회계 질의** | tax_agent.sh | Claude(해석) | 기본=Gemini Flash / `--codex`=gpt-5.2(웹검색+출처) / `--pro`=Gemini Pro |
| **전문직 Q&A** | expert_agent.sh | — | `doctor`/`lawyer` + 동일 플래그 지원 |
| **콘텐츠 집필** | content_pipeline.sh | — | 기본=Gemini Flash / `--codex`=gpt-5.2(문장품질↑) |
| **이미지 프롬프트** | image_agent.sh | — | Gemini Flash → DALL-E 3 / MJ / SD 3종 프롬프트 생성 |
| **영상 편집** | video_edit.sh (FFmpeg) | Gemini(ai 명령) | `brew install ffmpeg` 필요, `ai` 명령은 설치 없이도 가능 |

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
| **Document writing** | Codex CLI | gpt-5.2 | 웹 검색 불필요, ChatGPT Pro 쿼터 활용 |
| **Summarization** | Codex CLI | gpt-5.2 | 텍스트 처리, 검색 불필요 |
| **Data processing** | Codex CLI | gpt-5.1 | 가공/변환, 코딩 모델 불필요 |
| **Translation (bulk)** | Codex CLI | gpt-5 | 대량 텍스트, 경량 모델 |
| **Research (web search)** | Gemini | 2.5 Flash | 웹 검색 필요한 리서치 |
| **Deep analysis** | Gemini | 2.5 Pro | Max 100/day, use sparingly |
| **Data analysis** | Claude Code | Sonnet | Direct execution |
| **Notion: 조사+콘텐츠+저장** | Gemini | Flash | MCP 직접 연결, 원스톱, 최저비용 |
| **Notion: DB 설계·편집·판단** | Claude Code | Sonnet | 기능 완전, 판단력 필요 |
| **Notion: 자동화 저장** | notion_db.py | — | AI 비용 0 |

> **라우팅 기준**: 웹 검색 필요 → Gemini / 웹 검색 불필요 → Codex CLI (ChatGPT 모델)
> Codex CLI에서 `-m gpt-5.2` 등으로 ChatGPT 모델 지정 가능. 코딩 모델(codex)은 코딩에만 사용.

## Codex 모델 선택 가이드

코딩 작업을 Codex에 위임할 때, 리스크/규모에 따라 모델을 선택:

| 등급 | 모델 | 사용 조건 |
|---|---|---|
| **Heavy** | gpt-5.3-codex | 대규모 리팩터/마이그레이션, 모노레포 동시 수정, 보안/결제/인증 영역, 테스트 빈약한 코드베이스 |
| **Default** | gpt-5.3-codex | 중간 규모 기능 추가/버그 수정, 컴포넌트 1-3개, API 1-2개 수준 |
| **Light** | codex-spark | 코드베이스 탐색, 설정값 확인, 오타/문구 수정, 문서 정리, TODO 목록화 |

**판단 기준**: "실패했을 때 비용"이 큰 작업 → Heavy, 그 외 → Default or Light

## Codex 운영 룰

1. **실패 시 모델 업그레이드보다 태스크 분할 우선** — 태스크를 더 쪼개고 done-criteria를 구체화
2. **탐색 → 수정 → 테스트 순서 강제** — task_brief에 Execution Order 항상 포함
3. **변경 금지 영역 명시** — No-touch 필드로 불필요한 리포맷/리네이밍 방지

## Gemini 운영 룰

1. **리서치 결과는 글머리 기호 위주** — 에세이/산문 금지. 표와 bullet points로 구조화.
2. **코딩 관련 리서치 → Tactical Map 모드** — 리서치 결과를 Codex가 바로 실행할 수 있는 구조(파일별 변경사항 + 검증 커맨드)로 출력. Orchestrator가 task_brief에 바로 붙여 넣기 가능.
3. **Flash가 기본, Pro는 예외적** — "교차 검증 + 추론 필요"할 때만 Pro. 대부분 Flash로 충분.
4. **코드 직접 작성보다 Tactical Map 우선** — Gemini가 코드를 쓰는 것보다 실행 계획을 작성하여 Codex에 넘기는 것이 품질과 효율 모두 우수.

## Trigger System 활용 (Orchestrator → Agent)

Orchestrator(Claude Code)가 에이전트에게 task_brief를 보낼 때, 트리거 번호를 프롬프트 앞에 붙여 출력 형식을 제어할 수 있다.

| 트리거 | 용도 | 예시 |
|---|---|---|
| **"2"** | 웹 검색 리서치 | `"2 React vs Svelte 비교"` → 소스 포함 검색 결과 |
| **"4"** | 비교 분석 | `"4 Next.js vs Remix"` → 표/bullet 형태만 |
| **"5"** | 결론 우선 | `"5 이 아키텍처의 위험 요소"` → 결론→근거→리스크 |

활용 시점: 단순 리서치가 아닌, 특정 포맷이 필요할 때 트리거로 출력을 제어.

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

---

## Task Coverage Map

이 오케스트레이션 시스템이 수행할 수 있는 작업의 전체 범위.

### 직접 수행 (자동화)

| 카테고리 | 예시 | 주 에이전트 |
|---|---|---|
| 웹 개발 | 랜딩페이지, SaaS, 대시보드, 포트폴리오 | Codex(구현) + Gemini(리서치) |
| 앱 개발 | React Native, Flutter, Next.js 풀스택 | Codex(코드) + Gemini(기술조사) |
| 스크립트/자동화 | Python 스크립트, 배치 처리, 크롤러 | Claude(소규모) / Codex(대규모) |
| 리팩토링 | 코드 구조 개선, 패턴 변경, 마이그레이션 | Codex(실행) + Claude(판단) |
| 리서치/분석 | 기술 비교, 트렌드 조사, 문서 요약 | Gemini(수집) + Claude(정리) |
| 데이터 파이프라인 | CSV 처리, DB 쿼리, 시각화 스크립트 | Claude(소규모) / Codex(대규모) |
| CI/CD, DevOps | GitHub Actions, Docker, 배포 파이프라인 | Codex(파이프라인) + Gemini(에러분석) |
| 코드 리뷰 | PR 리뷰, diff 분석, 보안 점검 | Claude(Sonnet subagent) |
| 번역/현지화 | 다국어 텍스트, i18n 파일 | Gemini(대량) + Claude(소량) |
| Notion 조사+작성 | 가이드북, 리포트 자동 저장 | Gemini(MCP 직접, 원스톱) |
| Notion DB·복잡한 편집 | 스키마 설계, 판단 필요 작업 | Claude(MCP 직접) |
| Notion 자동화 저장 | AI 없이 결과 저장 | notion_db.py(비용 0) |
| Slack | 메시지 조회/작성 | Claude(MCP 직접) |
| Google 생태계 | YouTube 자막 분석, Drive 문서, Docs | Gemini(네이티브) |
| 대용량 문서 처리 | 50+ 페이지 PDF, PPT, 스펙 문서 | Gemini(분석) → Claude(요약) |

### 반자동 (Handoff — 사용자 실행 필요)

오케스트레이션이 구체적 지시서를 생성하고, 사용자가 해당 도구에서 실행.

| 카테고리 | 도구 | 오케스트레이션 역할 |
|---|---|---|
| UI/UX 디자인 | Figma | 디자인 스펙, 컴포넌트 구조, 토큰 정의 |
| 이미지 생성 | Midjourney | 프롬프트 + 파라미터(--ar, --v 등) |
| 프레젠테이션 | Gamma | 슬라이드 구조, 콘텐츠, 레이아웃 |
| 음악 생성 | Suno | 장르/무드/길이 프롬프트 |
| 영상 생성 | Kling | 씬 분해, 카메라 지시 |

### 조합 워크플로우 예시

| 프로젝트 | 흐름 |
|---|---|
| SaaS 랜딩페이지 | Gemini(레퍼런스 조사) → 사용자(방향 선택) → Codex(코드 구현) → Figma handoff(디자인) → Midjourney handoff(히어로 이미지) |
| 사업 보고서 | Gemini(시장 데이터 수집) → Claude(구조화/분석) → Gamma handoff(발표 자료) |
| 모바일 앱 | Gemini(기술 스택 비교) → 사용자(선택) → Codex(스캐폴딩+구현) → Figma handoff(UI) |
| 데이터 분석 | Claude(소규모 스크립트) or Codex(대규모 파이프라인) → Gemini(결과 해석) |
| 오픈소스 기여 | Gemini(이슈/코드 분석) → Codex(구현) → Claude(PR 리뷰+커밋) |

### 현재 미지원

| 영역 | 이유 | 대안 |
|---|---|---|
| 실시간 협업 (Figma 직접 조작) | API/CLI 없음 | Handoff 문서 |
| 모바일 실기기 테스트 | 물리 디바이스 필요 | 에뮬레이터 스크립트까지 |
| 결제/인증 실서비스 연동 | 실 credentials 위험 | 코드 + 설정 가이드 |
| 디자인 에셋 직접 생성 | Midjourney/DALL-E CLI 없음 | 프롬프트 Handoff |
