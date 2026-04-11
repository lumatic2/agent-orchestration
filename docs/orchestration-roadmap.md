# AI Orchestration Roadmap — Big Picture

> agent-orchestration의 다음 진화 방향. 현재 상태, 업그레이드 공간, 선정된 경로.
> 작성: 2026-04-08 | 2세대 로드맵 추가: 2026-04-11

## 현재 상태 (2026-04-08 기준)

- **구조**: Claude Code가 유일한 오케스트레이터. Codex/Gemini는 Skill 플러그인(`codex:rescue`, `gemini:rescue`)을 통해 1회성 위임만 받는 워커
- **통신**: 파일 기반 (SHARED_PRINCIPLES.md, adapters/*, ~/AGENTS.md, ~/CLAUDE.md) + Skill CLI 래퍼
- **공통 원칙 통일**: `sync.sh`가 SHARED_PRINCIPLES를 Claude/Codex/Gemini 설정 파일에 정적 주입. 세 기기(Windows/Mac Air/M4) 배포 완료
- **한계**: 1차원 위임만 됨 — Claude가 Codex한테 일 시키고, Codex는 결과만 돌려줌. 에이전트 간 대화, 병렬 작업, 장시간 자율 루프, 적대적 협업 등의 고차 패턴 없음

## 업그레이드 공간 4개 축

| 축 | 현재 | 가능한 업그레이드 |
|---|---|---|
| **통신 패턴** | 1회성 위임 | 다중 턴 대화, 공유 작업 메모리, 에이전트 간 직접 교류 |
| **구조** | 평평 (Claude 단독 조율) | 계층(planner→sub→executor), 병렬, 토론/스왐 |
| **자율성** | 사용자 단계별 트리거 | 장시간 실행, 목표 주도 루프, 자가 교정 |
| **프로토콜** | 파일 + Skill CLI | MCP 기반 에이전트 노출, A2A 프로토콜, 벡터 공유 메모리 |

## 3가지 유망 방향

### 방향 1 — 적대적 리뷰 파이프라인 (Adversarial Review Chain) ⭐ **프로토타입 완료 (2026-04-08)**

> 1회 실증 완주: Claude의 tool calling만으로 `codex_run` → `gemini_run`(리뷰) → Claude 심판 → `codex_run`(resume) 체인 검증. 1차 코드의 HIGH-severity silent-wrong-answer 4개를 리뷰가 잡고 2차에서 explicit ValueError로 전환됨.
> 세션 로그: [`../examples/adversarial-review.md`](../examples/adversarial-review.md) · 복붙 템플릿: [`../examples/adversarial-review-template.md`](../examples/adversarial-review-template.md)
> 잔여: gemini-3-flash-preview hang 빈도가 높아 "Claude 직접 리뷰" fallback이 사실상 기본 경로. flash 안정화되면 진짜 2-에이전트 체인으로 승격.

**흐름**: Claude 계획 → Codex 구현 → Gemini 적대적 리뷰("이 코드를 깨뜨려봐") → Claude 심판 → 필요 시 Codex 재시도

**장점**:
- 현재 인프라에 거의 손대지 않고 가능. `scripts/review-pipeline.sh` 수준
- 두 모델의 다른 훈련 데이터로 blind spot 보완 (Codex가 놓친 걸 Gemini가 잡고, 역도 성립)
- 즉시 효용 체감. 구현 1-2시간

**단점**:
- 구조적 업그레이드가 아니라 *사용 패턴* 업그레이드. 근본적 스케일업은 아님
- 병렬·계층 패턴으로 확장하기 어려움 (여전히 1차원)

**ROI**: 즉시 유용, 장기 기반은 아님

---

### 방향 2 — Codex/Gemini를 MCP 서버로 노출 ⭐ **선정 / 프로토타입 완료 + A2A 검증 (2026-04-08)**

> 구현체: [`../mcp-servers/`](../mcp-servers/) · 상세 문서: [`mcp-servers.md`](./mcp-servers.md)
> Phase 1~6 완료 (스캐폴딩 → codex-mcp → gemini-mcp → Claude Code 등록/스모크 → JSON.parse 버그 fix → 문서화 → auto-poll wrapper).
> **A2A 단계 도달**: Codex CLI와 Gemini CLI가 양쪽 다 MCP 클라이언트 모드를 네이티브 지원하는 것을 확인하고, Codex 세션에서 gemini-mcp를 호출하고 Gemini 세션에서 codex-mcp를 호출하는 양방향 왕복을 1회씩 검증함 (2026-04-08). Cursor/Windsurf 실사용 검증은 여전히 후속 작업.


**아이디어**: Codex CLI와 Gemini CLI를 MCP(Model Context Protocol) 서버로 래핑. 기존 `Skill("codex:rescue", ...)`는 Claude Code 전용이지만, MCP 서버는 Cursor, Windsurf, Continue, 심지어 Codex/Gemini 서로서로 어느 MCP 클라이언트에서도 도구로 호출 가능.

**장점**:
- **계층/병렬/토론 패턴의 기반 인프라**가 됨. 한 번 깔면 방향 1도 훨씬 자연스럽게 구현됨 (Claude가 MCP로 Codex를 부르고, Codex가 MCP로 Gemini를 부르는 체인 가능)
- Anthropic MCP 생태계 모멘텀 편승. 점점 더 많은 도구가 MCP로 통합 중
- 에이전트를 "도구"로 취급 가능 — 이건 CrewAI/LangGraph 같은 Python 프레임워크 도입 없이도 멀티 에이전트 조합을 가능하게 함
- 단기적으로는 효용이 작아도 **후속 작업의 승수 효과**가 큼

**단점**:
- MCP 서버 구현 학습 곡선 (Node.js/Python SDK)
- 기존 Skill 플러그인과 중복될 수 있음 — 정리 필요
- 당장의 워크플로에는 큰 변화 없음

**ROI**: 단기 중간, 장기 최대

---

### 방향 3 — 장시간 Deep Research 모드 (Gemini Pro 기반) ⭐ **B 패턴 채택 / Step 5 완료 (2026-04-10)**

> 인프라 베이스라인: [`../examples/deep-research-template.md`](../examples/deep-research-template.md) (복붙 템플릿) · 4 프롬프트: [`../examples/prompts/research-{scope,skeptic,judge,final}.md`](../examples/prompts/)
> 실증 세션 로그: [`../examples/deep-research.md`](../examples/deep-research.md) (Session 1~3, Step 4a/b 결정, Step 5 진행 상태 전부 여기에)

**흐름**: 한 줄 리서치 질문 → Claude(scope) → Round N { Gemini(Proposer) ×3 병렬 → Codex(Skeptic) → Claude(Judge) } → 수렴 → 최종 보고서 → vault 승인 게이트

**Step 4a (B 패턴 실증)** — 완료:
- Session 1 (long-context benchmarks, arxiv-heavy, coverage 25%) · Session 2 (agent frameworks, blog/github-heavy, capacity exhaustion abort) · Session 3 (long-context benchmarks 재현, arxiv-heavy, coverage 42%)
- Done 기준 7/7 충족 (Session 3 R2 완주로 coverage-full + wall-clock 자연 종료 관측)

**Step 4b (분기 결정)** — 완료 (2026-04-09):
- **B (Proposer + Skeptic + Judge) 패턴 채택**. C (multi-round agentic tree) 는 현 단계 불필요 — branch 발산은 scope 프롬프트 수준에서 해결됨
- **3 필수 정책**: (a) Skeptic URL verification 필수, (b) sequential Gemini launch 25s gap (Session 2 #11 position effect 회피), (c) arxiv-heavy + 오전 시간대 + capacity 여유 확인 후 재현성 검증 범위
- 근거: Session 1/3 교차 검증 — diversified branch + Skeptic 0% false positive + Attack 1b heuristic 7 이 fabricated URL 4건 실전 탐지

**Step 5 (마무리)** — 5-D 잔여:
- 5-A 템플릿 개정 (Session 3 교훈 반영): 완료
- 5-B 자연 종료 관측: **완료** (Session 3 R2 — coverage-full 83.3% + wall-clock 36min, Done 7/7)
- 5-C vault end-to-end 승인 게이트: 완료
- 5-D blog/github heavy 재검증: **완료** (Session 4, 2026-04-10) — Gemini pro 5/5 성공 (capacity abort 0), coverage 70% (wall-clock 종료). blog/github-heavy에서 B 패턴 작동 확인. 단 Round 1 소스 품질이 구조적으로 낮으므로 `max_rounds ≥ 2` 필수.

**관련 MCP 인프라**: [`mcp-servers.md`](./mcp-servers.md) §9 (output validation), §10 (capacity), §11 (position), §12 (content-less confabulation) — Deep Research 실증이 발굴한 MCP 하부 개선사항들

---

## 선정 결과: 방향 2

**근거**:
- 방향 1과 3은 방향 2 위에 올리면 자연스럽게 구현됨 (MCP로 Codex가 노출되면 리뷰 체인도, Deep Research 중 Codex 호출도 쉬워짐)
- 장기 기반 투자. 지금 깔아두면 반년 안에 여러 후속 작업의 공통 인프라가 됨
- Anthropic MCP 생태계 모멘텀 편승 — 표준화된 방향

**실행 순서 (예상)**:
1. MCP 서버 오픈소스 예시 조사 (Python/Node.js SDK, CLI 래퍼 패턴)
2. `codex-mcp` 서버 프로토타입 (Codex CLI 호출 → MCP 도구로 노출)
3. `gemini-mcp` 서버 프로토타입
4. `~/.claude/settings.json`의 MCP 서버 목록에 등록
5. 기존 Skill 플러그인과의 관계 정리 (유지 vs 제거 vs 공존)
6. 다른 MCP 클라이언트(Cursor 등)에서 호출 검증

**후속으로 풀릴 일들**:
- 방향 1 (적대적 리뷰): Claude가 Codex MCP 호출 → Codex 결과를 Gemini MCP에 넘겨 리뷰 요청 — 별도 스크립트 없이 Claude의 tool calling으로 자연 체이닝
- 방향 3 (Deep Research): Gemini MCP를 받아 Claude가 "continuation loop"를 직접 돌리거나, 별도 Deep Research 에이전트가 Gemini MCP + 웹 MCP를 조합해서 사용

## Step 5 결정: Plugin(Skill) ↔ MCP 공존 유지 (2026-04-10)

> 실행 순서 §5 "기존 Skill 플러그인과의 관계 정리" 완료.

### 세 레이어의 역할 구분

```
Plugin (배포 패키지)
  └─ Skill/Command/Hook/Agent (Claude Code 전용 고수준 인터페이스)
       └─ companion 스크립트 (공통 런타임)
MCP Server (범용 저수준 인터페이스)
       └─ 같은 companion 스크립트 호출
```

| 레이어 | 정체 | 쓸 수 있는 곳 | 제공하는 것 |
|---|---|---|---|
| **Plugin** | 배포 패키지 (`enabledPlugins`로 활성화) | Claude Code 전용 | skills + commands + hooks + scripts + agents 묶음 |
| **Skill** | Plugin 안의 개별 기능 (`/codex:rescue` 등) | Claude Code 전용 | 프롬프트 가이드 + 에러 핸들링 + 결과 포맷팅 |
| **MCP Server** | 우리가 만든 프로토콜 어댑터 (`codex-mcp` 등) | 아무 MCP 클라이언트 (Cursor, Windsurf, Codex, Gemini...) | 순수 도구 인터페이스 (JSON-RPC) |

### 겹치는 기능과 결정

| 기능 | Skill | MCP | 겹침 |
|---|---|---|---|
| 작업 위임 | `codex:rescue`, `gemini:rescue/research` | `codex_run/task`, `gemini_run/task` | ✅ 동일 job queue |
| 상태/결과/취소 | `codex:status/result/cancel`, `gemini:*` | `codex_status/result/cancel`, `gemini_*` | ✅ 동일 job queue |
| 코드 리뷰 | `codex:review`, `gemini:review` | ❌ 없음 | Skill 전용 |
| 적대적 리뷰 | `codex:adversarial-review` | ❌ 없음 | Skill 전용 |
| 설정/가이드 | `codex:setup`, 내부 prompting skills | ❌ 없음 | Skill 전용 |

**결정: 공존 유지.**

- Skill은 Claude Code 안에서 풍부한 UX(프롬프트 컨텍스트, 에러 가이드, 포맷팅)를 제공하는 고수준 래퍼
- MCP는 같은 companion/job store를 외부 클라이언트에 노출하는 저수준 어댑터
- 같은 job store를 공유하므로 충돌 없음 — Skill로 시작한 job을 MCP로 조회 가능, 역도 성립
- review/adversarial-review 등 Skill 전용 기능은 MCP 쪽에 당장 추가 불필요 (Cursor 검증 시 재평가)

### 후속 과제

- [x] §6 Cursor 실사용 검증 완료 (2026-04-10) — codex-mcp 5 tools + gemini-mcp 5 tools 정상 로드, codex_run/gemini_run 실제 호출 성공
- [x] §6 review 도구 MCP 노출 불필요 결정 (2026-04-10) — Claude Code Skill 전용으로 충분, MCP 추가 안 함
- [x] Stitch MCP 서버 등록 완료 (2026-04-10) — `auto-stitch-gc5y6t` GCP 프로젝트 연동, Claude Code + Cursor 양쪽 등록

## 의도적으로 배제한 경로

- **LangGraph / CrewAI / AutoGen**: Python 프레임워크 기반. 현재 Bash + CLI + MCP 구조와 임피던스 미스매치. 도입 시 기존 sync.sh/Skill 인프라를 거의 버려야 함
- **OpenAI Swarm**: OpenAI 중심. Claude Code 생태계와 맞물리기 어려움
- **Devin-style 완전 자율**: 구현 노력 대비 ROI 낮음 (Codex가 이미 부분적으로 수행)

## 참고 자료 수집 필요

- MCP Python SDK (`mcp` 패키지) 또는 TypeScript SDK 공식 문서
- 기존 CLI 래핑 MCP 서버 예시 (예: `mcp-server-git`, `mcp-server-fetch`)
- Codex CLI의 비대화형 인터페이스 사양 (이미 codex-companion.mjs가 있음 — 참고)
- Gemini CLI의 비대화형 인터페이스 사양
- Anthropic MCP 공식 레지스트리에서 "agent-as-tool" 사례

→ 다음 세션에서 타겟 리서치 + 프로토타입 시작

---

## 2세대 로드맵 (2026-04-11 ~)

> 1세대(방향 1~3)가 완료된 이후, 더 고급진 오케스트레이션으로 진화하는 4개 Phase.
> 전제: MCP 3-에이전트 인프라, A2A 양방향 검증, adversarial chain, deep research 모두 완료된 상태.

### 현재의 구조적 공백

| 한계 | 증상 |
|---|---|
| 세션 간 기억 없음 | 같은 리서치를 Gemini가 매번 처음부터 수행 |
| 실행이 항상 순차적 | 병렬 gather 요청을 Claude가 머릿속으로만 처리 |
| 라우팅이 정적 Markdown | 실적 데이터가 쌓여도 라우팅 규칙이 바뀌지 않음 |
| 사용자가 매번 트리거 | git push, 이상 신호 등 이벤트에 에이전트가 반응 못 함 |

---

### Phase A — 공유 메모리 레이어 (Agent Memory Layer) 🚧 **진행 중**

> 가장 큰 구조적 공백 해소. 모든 후속 Phase의 기반.

**목표**: `memory-mcp` MCP 서버 구축 — 에이전트들이 세션을 넘어 지식을 공유

**설계**:
- SQLite + 임베딩(sqlite-vec 또는 chromadb) 기반 로컬 벡터 저장소
- MCP 도구 4종: `memory_store`, `memory_recall`, `memory_list`, `memory_delete`
- 메모리 유형: `research` (리서치 요약), `decision` (라우팅 결정 근거), `code_pattern` (코드 패턴), `fact` (검증된 사실)
- 저장 경로: `mcp-servers/memory-mcp/`
- 동일한 `data/` 폴더 접근 — Codex/Gemini job store와 공존

**기대 효과**:
- Gemini가 deep research 결과를 저장 → 다음 관련 질문 시 재사용
- adversarial review에서 과거 패턴 참조 ("이 타입의 버그는 전에도 나왔음")
- Claude가 라우팅 결정 근거를 축적 → Phase C 자가 진화의 원재료

**완료 기준**:
- [ ] `memory-mcp` MCP 서버 스캐폴딩 (Node.js, codex-mcp 패턴 동일)
- [ ] SQLite + 임베딩 도구 4종 구현
- [ ] Claude Code에 등록 + 스모크 테스트
- [ ] `memory_store` / `memory_recall` 실전 호출 1회 확인

---

### Phase B — 워크플로 DAG 엔진 (Structured Parallel Execution)

> Claude 머릿속의 라우팅을 선언형 YAML로 외부화 → 진짜 병렬 실행 실현

**목표**: YAML 워크플로 정의 → Python 실행기가 DAG 해석 → 병렬 에이전트 호출

**설계 예시**:
```yaml
task: "competitive analysis"
dag:
  scope:   { agent: claude, output: spec }
  gather1: { agent: gemini, input: spec, topic: "player A", parallel_group: gather }
  gather2: { agent: gemini, input: spec, topic: "player B", parallel_group: gather }
  gather3: { agent: gemini, input: spec, topic: "player C", parallel_group: gather }
  skeptic: { agent: codex,  input: [gather1, gather2, gather3], depends_on: gather }
  judge:   { agent: claude, input: skeptic }
```

- 실행기: `pipeline/dag_runner.py` (경량 Python, 외부 의존성 최소화)
- Mermaid 다이어그램 자동 생성 → 진행 상태 시각화
- 기존 deep-research-template.md의 B 패턴을 DAG로 공식화

**전제 조건**: Phase A 완료 (노드 간 결과 전달을 메모리 레이어로)

---

### Phase C — 자가 진화 라우팅 (Adaptive Routing)

> ROUTING_TABLE.md를 데이터 기반으로 자동 보정

**목표**: 실적 데이터 축적 → 라우팅 드리프트 감지 → 제안 PR 자동 생성

**설계**:
- 각 작업 완료 시 메타데이터 태깅: `{ task_type, agent, model, quality_score, latency_s }`
- 주기적 집계 스크립트 (`scripts/routing-audit.sh`)
- 임계치 초과 시 ROUTING_TABLE.md 수정 PR 자동 생성 (사람 승인 필수 유지)

**전제 조건**: Phase A 완료 (메타데이터 저장소로 memory-mcp 활용)

---

### Phase D — 이벤트 기반 자율 루프 (Reactive Orchestration)

> 사용자 트리거 없이 에이전트가 이벤트에 반응

**목표**: file/webhook 이벤트 → 에이전트 자동 실행 → 결과 알림

**유스케이스**:
- `git push` → adversarial review 자동 실행
- 투자봇 이상 신호 감지 → Gemini 분석 → Telegram 알림
- 새 데이터 파일 감지 → 자동 파이프라인 실행

**설계**:
- 기존 `job-watcher` 위에 event subscription 레이어 추가
- 이벤트 유형: `file_change`, `git_push`, `cron`, `webhook`
- 에이전트 응답 로직을 `config/event-rules.yaml`에 선언

**전제 조건**: Phase B 완료 (DAG 엔진으로 에이전트 실행 표준화)

---

### 실행 순서 요약

```
Phase A: memory-mcp       ← 지금 시작. 2~3일. 즉시 체감 효과 + 후속 Phase 기반
Phase B: DAG 엔진         ← Phase A 완료 후. 1주. 병렬 orchestration 실현
Phase C: 자가 진화 라우팅 ← Phase A 완료 후. 데이터 쌓이면 자연스럽게
Phase D: 이벤트 루프      ← Phase A+B 완료 후. 가장 높은 자율성
```
