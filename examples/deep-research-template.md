# Deep Research (B — adversarial pair) — Template

> 새 Claude Code 세션에 복사해서 쓸 수 있는 Deep Research 프롬프트.
> Gemini(Proposer) + Codex(Skeptic) + Claude(Judge) 적대적 리서치 쌍.
>
> 실제 1회분 세션 예시: [`deep-research.md`](./deep-research.md)
> 프롬프트 4종: [`prompts/research-scope.md`](./prompts/research-scope.md),
> [`prompts/research-skeptic.md`](./prompts/research-skeptic.md),
> [`prompts/research-judge.md`](./prompts/research-judge.md),
> [`prompts/research-final.md`](./prompts/research-final.md)

## 사용법

새 Claude Code 세션에서:

```
다음 질문을 Deep Research (B 패턴) 로 진행해:

[원질문 — 한 줄~한 단락. 무엇을 알고 싶은지, 왜 알고 싶은지, 어떤 결정에 쓸지]

체인 규칙은 ~/Projects/agent-orchestration/examples/deep-research-template.md 를 따라.
```

Claude 는 아래 단계를 자동 수행한다.

## 전제 조건

- `mcp__codex-mcp__codex_run` / `mcp__gemini-mcp__gemini_run` 도구 노출
- Gemini 계정이 `gemini-3.1-pro-preview` 접근 가능 (Deep Research 기본 모델)
- wall clock 여유 (기본 30분, 하드 캡 60분)
- vault 저장 권한 (`mcp__obsidian-vault__write_note`) — 최종 단계에서 승인 게이트 통과 시

### ⚠️ Windows 사용자 경고 — 터미널 창을 닫지 마세요

`gemini_run` 병렬 3 branch 를 발사하면 Gemini CLI 가 **보이는 터미널 창** 을 각 branch 당 1 개씩 spawn 한다 (Windows 환경 특이점). 이 창을 수동으로 닫으면 해당 branch 는 즉시 빈 문자열로 반환되고 `status: "completed"` 로 보고된다 (MCP wrapper 가 빈 출력을 실패로 감지 못함 — `docs/mcp-servers.md` 후속 개선 #9 참조). 창은 Gemini 응답 수신 후 자동 종료되므로 **내버려 두라**. Session 1 실증에서 이 실패가 먼저 발견됐다.

## 체인 구성

```
Claude(scope)
  └─▶ success_criteria checklist 생성
       │
       ▼
┌─ [Round 1] ──────────────────────────────────────────┐
│ Gemini(Proposer) × 3 병렬                            │
│   gemini_run(model=pro, timeoutMs=900000)            │
│     ↓                                                │
│ Codex(Skeptic)                                       │
│   codex_run(read-only, timeoutMs=600000)             │
│     ↓                                                │
│ Claude(Judge)                                        │
│   수용 필터 → 생존 claim → coverage 업데이트         │
│   → 종료 조건 체크 → 다음 쿼리 OR 종료               │
└──────────────────────────────────────────────────────┘
       │
  (loop until termination)
       ▼
Claude(final report) → data/deep-research/{slug}/report.md
       ↓
사용자 승인 게이트
       ↓
vault → 10-knowledge/research/{slug}.md
```

## 단계

### 0. Scope (Claude 직접)

1. `examples/prompts/research-scope.md` 프롬프트 본문의 YAML 스키마대로 scope 출력
2. `success_criteria` 3~7 개 checkable 항목으로 작성
3. `slug` 결정 → `data/deep-research/{slug}/` 디렉토리 생성
4. 사용자에게 scope YAML 보여주고 **1초만** 대기 — 명백히 잘못됐으면 수정, 아니면 진행

### 1. Round 루프

각 라운드에서:

#### 1a. Gemini Proposer — 병렬 3

```js
// 3 개 쿼리를 한 번에 병렬 발사
mcp__gemini-mcp__gemini_run({
  prompt: `<Round 1이면 scope 기반 3 개 diversified 쿼리 중 1개,
           Round N>1이면 Judge 단계에서 생성된 다음 라운드 쿼리 중 1개>`,
  model: "pro",
  timeoutMs: 900000   // 15분 — Deep Research 한정 override
})
```

Round 1 쿼리 생성 규칙:
- 쿼리 1: scope 의 "가장 기본적인 정의/개요" 타겟
- 쿼리 2: scope 의 "최신 상태 / 벤치마크 / 수치 비교" 타겟
- 쿼리 3: scope 의 "반례 / 제약 / 실패 사례" 타겟 (발산 확보)

각 쿼리 본문에 공통 포함:
```
Required source types: primary papers, vendor docs, benchmark repos, case studies.
Do NOT rely on blog posts or marketing material. Cite source URL and year.
Time range: <scope.intent.when>

CRITICAL — Anti-fabrication policy (added 2026-04-09 after Session 2/3):
If you cannot find a real source for a claim, LEAVE IT BLANK. Do NOT invent
URLs. Do NOT synthesize arxiv ids. Do NOT cite famous venues (arxiv, ACL,
NeurIPS, aclanthology) from memory — only cite them if you actually
retrieved them in this search. If the answer to a sub-question is "no
such paper exists" or "literature is silent on this", report EXACTLY that.
A negative finding is a valid finding. A fabricated citation is a
critical failure that will be caught by the Skeptic and will drop the
entire claim.

Known failure modes to AVOID:
- arxiv id format violations (e.g. `2507.30` instead of `2507.30000`)
- citing a real arxiv/aclanthology URL whose paper is on an unrelated topic
- Medium/Substack URLs with repeated-character slugs (`0f1b1b1b1b1b`)
- filling gaps in "counter-argument" requests with synthesized citations
```

#### 1b. Diff 수집 불필요 (리서치라서)

바로 Skeptic 단계로.

#### 1c. Codex Skeptic

```js
mcp__codex-mcp__codex_run({
  prompt: `<examples/prompts/research-skeptic.md 본문>\n\n## Material\n\n${gemini_outputs_concatenated}`,
  cwd: "C:/Users/1/Projects/agent-orchestration",
  // write 플래그 없음
  timeoutMs: 600000
})
```

Gemini 출력 합치는 형식:
```
--- branch 1 (gemini-pro) ---
<query>
<output>

--- branch 2 (gemini-pro) ---
<query>
<output>

--- branch 3 (gemini-pro) ---
<query>
<output>
```

#### 1d. Claude Judge

`examples/prompts/research-judge.md` 규칙대로:
1. Skeptic 지적 필터
2. Claim 생존 판정
3. Coverage 업데이트
4. 종료 조건 체크
5. 종료 or 다음 라운드 쿼리 3 개 생성
6. 라운드 로그 기록 → `data/deep-research/{slug}/round-N.md`

#### 1e. 사용자 업데이트

라운드 종료 시 짧게 보고:
```
Round N 완료 — coverage X/Y (Z%), 수용된 Skeptic 지적 M 개, 소요 T 분
다음 라운드 쿼리 주제: [...]
계속 진행합니다.
```

사용자 응답 대기 안 함 (자율 루프). STOP 파일로 수동 중단 가능.

### 2. 종료

종료 조건 중 하나 발동 → Judge 가 종료 선언 → `research-final.md` 템플릿으로 최종 보고서 작성.

### 3. vault 승인 게이트

`data/deep-research/{slug}/report.md` 스테이징 → 사용자에게:
```
Deep Research 보고서 준비 완료:
- slug: <slug>
- rounds: N
- coverage: X/Y (Z%)
- wall clock: M 분
- termination: <reason>
- 스테이징: data/deep-research/{slug}/report.md

vault 저장 원하시면 승인해주세요.
```

승인 시에만 `mcp__obsidian-vault__write_note` 호출.

## Fallback

### Gemini pro pre-check (Round 시작 전 필수, 2026-04-09 Session 3 R2 교훈)

Round 1 발사 직전, 또는 Round N 중간 재개 직전, 반드시 `gemini_run(model="pro", prompt="<10토큰 probe>")` 1회 실행:

- **통과** (정상 출력): Round 진행
- **`MODEL_CAPACITY_EXHAUSTED`** 또는 **DEGRADED** (attempt 1 실패 → backoff 후 attempt 2 성공): **즉시 abort + 재시도 스케줄링**. 해당 라운드 발사 금지. Judge 로그에 `capacity-exhaustion-abort` 기록. 사용자에게 "현재 Gemini pro capacity 부족, [제안 시간] 재시도" 보고. autoloop 재개 전 pre-check 재실행 필수.
- **근거**: Session 3 R2 (2026-04-09 10:40 KST) 에서 오전 × arxiv-heavy (이전에 safe 로 검증된 조건) 에도 불구하고 capacity exhaustion 발생. 시간대·도메인 제어만으로는 capacity 를 보장할 수 없음 — Google 일일 capacity 변수는 독립축.

### Gemini pro hang / 429 (Round 진행 중)

1. 해당 branch 만 `gemini_cancel`
2. 1회 재시도 (timeoutMs 절반)
3. 재시도 실패 → 해당 branch 는 빈 결과로 진행 (나머지 2 개로 라운드 계속)
4. 3 branch 모두 실패 → 라운드 스킵 + Judge 가 "Gemini 전체 실패" 로그 + 다음 라운드 재시도
5. 2 라운드 연속 3/3 실패 또는 pro capacity 완전 exhaustion → `capacity-exhaustion-abort` 로 체인 중단 + 사용자 보고

⚠️ Step 2 실증에서 `gemini-3-flash-preview` hang 빈도 높았음. pro 는 상대적으로 안정하지만 여전히 가능. 3 branch 분산이 1차 보험.

### Codex Skeptic timeout / 무응답

- timeout: Gemini 출력이 너무 큰 신호. 다음 라운드 `parallel_gemini` 를 2 로 줄임.
- 빈 응답 / "looks fine" 만: Judge 가 "유효 반박 생성 실패" 로 카운트. 2 연속이면 종료 조건 발동 (Skeptic 실패).
- 세션 좀비: `codex_cancel` → 실패 시 `cmd //c "taskkill /PID <pid> /T /F"` (Step 2 세션 관찰 반영)

### wall clock 도달

Judge 가 즉시 종료 선언. 다음 라운드 진입 금지. 이미 쌓인 라운드로 최종 보고서 작성.

## 절대 금지

- Scope 단계 건너뛰기 (success_criteria 없으면 종료 조건 `max_rounds` 뿐)
- Round 1 이후 2회 이상 checklist 재작성 (goal-post 이동)
- Gemini 출력을 Claude 가 무비판 수용 (반드시 Skeptic → Judge 경유)
- Skeptic 출력을 Claude 가 무비판 수용 (false positive 필터링 필수)
- Judge 단계에서 Claude 가 스스로 claim 추가 (Judge 는 필터이지 생성자 아님)
- 사용자 승인 없이 vault 저장
- wall clock 하드 캡 60분 초과

## 적합 / 부적합 질문

**적합**:
- 기법/도구 비교 ("X 와 Y 중 어느 것이 Z 상황에 적합한가")
- 최신 state-of-the-art 조사
- 결정 근거 수집 (기술 선택, 아키텍처 선택)
- 벤치마크·정량 비교가 중요한 질문
- 반대 증거가 존재할 가능성이 있는 영역

**부적합**:
- 단일 fact lookup ("X 의 발표년도?") — 일반 WebSearch 가 빠름
- 주관적 질문 ("가장 좋은 OS 는?") — checkable criteria 불가
- 시뮬레이션/실험이 필요한 질문 (Deep Research 는 증거 수집일 뿐)
- 내부 코드베이스 조사 (Grep/Glob 가 빠름)
- 1시간 안에 끝날 가능성이 없는 초대형 조사 (wall clock cap 초과)

## 기본값

- max_rounds: 5
- wall_clock_minutes: 30 (하드 캡 60)
- parallel_gemini: 3
- gemini_model: pro
- gemini_timeout_ms: 900000
- codex_timeout_ms: 600000
- checklist 재작성: max 1회 (Round 1 이후)
- 재시도 상한: Gemini branch 1회, 라운드 스킵 2 연속 시 중단

위 기본값을 벗어나고 싶으면 scope YAML 의 `constraints` 섹션에 명시.
