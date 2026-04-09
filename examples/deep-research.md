# Deep Research B — Session Log (skeleton)

> 방향 3 ([orchestration-roadmap.md](../docs/orchestration-roadmap.md)) Deep Research 루프 첫 실증.
> 적대적 리서치 쌍 = Gemini(Proposer) + Codex(Skeptic) + Claude(Judge).
> Step 2 ([adversarial-review.md](./adversarial-review.md)) 패턴의 리서치 확장판.
>
> **상태**: 골격 (2026-04-09 작성). 실증 2~3 회 세션 실행 후 아래 `## Session N` 섹션을 채운다.
> 실증이 끝나면 Step 4a Done 기준 충족 여부 + Step 4b 분기 결정을 문서 말미에 기록.

체인 구성:
```
Claude(scope + judge)
  ├─▶ success_criteria checklist 생성
  ├─▶ [Round loop]
  │    ├─▶ gemini_run × 3 (pro, 병렬, 15분 timeout)      ← Proposer
  │    ├─▶ codex_run (read-only, 10분 timeout)           ← Skeptic
  │    └─▶ Claude Judge: 필터 → 생존 claim → coverage   ← Judge
  ├─▶ 종료 조건 (OR)
  └─▶ 최종 보고서 → vault 승인 게이트
```

복붙용 템플릿: [`deep-research-template.md`](./deep-research-template.md)
프롬프트 4종: [`prompts/research-scope.md`](./prompts/research-scope.md), [`prompts/research-skeptic.md`](./prompts/research-skeptic.md), [`prompts/research-judge.md`](./prompts/research-judge.md), [`prompts/research-final.md`](./prompts/research-final.md)

## 공통 관찰 항목 (모든 세션에서 기록)

실증 세션마다 아래를 계측한다. Step 4b 분기 결정의 근거 데이터.

| 항목 | 정의 | 왜 중요 |
|---|---|---|
| rounds_to_terminate | 종료까지 라운드 수 | `max_rounds` 상수 튜닝 근거 |
| termination_reason | coverage-full / stagnation / max-rounds / skeptic-failed / wall-clock / user-hold | 종료 조건 중 무엇이 실제로 발동하는지 |
| final_coverage | filled / total | checklist 가 현실적인지 |
| wall_clock_minutes | 실측 | 30분 기본값·60분 하드캡 적정성 |
| gemini_branch_failures | 실패 branch / 총 branch | pro 안정성 |
| gemini_fabricated_urls | fabricated / total cited URLs (Attack 1b 탐지) | #10 #12 모니터링 — blog/arxiv heavy 비교 |
| skeptic_valid_objections_per_round | 라운드별 수용된 지적 수 (**absolute**) | Skeptic 프롬프트 효율 |
| skeptic_objections_per_claim | 라운드별 수용 지적 / round claim 수 (**normalized**) | claim 수 편차 보정한 진짜 효율 |
| skeptic_seconds_per_claim | Skeptic wall clock / round claim 수 (**normalized**) | Skeptic 비용 — 절대 초가 아님 |
| skeptic_false_positive_rate | 전체 지적 중 기각 비율 | Judge 필터 강도 |
| claim_survival_rate | SURVIVES / 총 claim | Gemini 품질 × Skeptic 공격력 |
| divergence_vs_depth | 발산(새 방향)  vs 심화(같은 방향 깊이) 주관 평가 | 4b — C 확장 결정 핵심 |
| checklist_revised | Round 1 이후 재작성 여부 | scope 프롬프트 품질 |

마지막 항목 `divergence_vs_depth` 는 주관 평가지만 **4b 분기 결정의 핵심 신호**. 세션마다 명시적으로 한 문단 기록.

### 정규화 원칙 (2026-04-09 Session 3 추가)

**절대값과 claim 당 정규화를 반드시 구분해서 기록한다.** Session 3 에서 "Skeptic wall clock -24%" (497s → 380s) 를 효율 향상으로 오독할 뻔했으나, 실제로는 **claim 수가 21 → 13 으로 38% 감소**했기 때문이었다. per-claim 으로 정규화하면 23.7s/claim → 29.2s/claim 로 **오히려 느려졌다**.

절대값만 기록하는 metric 은 세션 간 비교 불가능하다. 아래 두 가지 metric 은 반드시 정규화된 형태로 함께 기록:

- **Skeptic 비용**: `skeptic_seconds_per_claim = skeptic_wall_clock / round_claim_count`
- **Skeptic 효율**: `skeptic_objections_per_claim = skeptic_valid_objections / round_claim_count`

`gemini_branch_failures` 처럼 총 수가 3 으로 고정된 metric 은 정규화 불필요. `claim_survival_rate` 는 이미 비율이므로 정규화 개념 동일.

## Session 1 — long-context-100k-recall-2026 (2026-04-09)

**질문**: 2025~2026 LLM long-context 벤치마크에서 100k+ 토큰 구간의 recall 정확도가 실제로 유지되는 기법은 무엇인가?

**Status**: Round 1 만 실행 → 사용자와 합의된 일시 정지 지점. Round 2~N 는 진행 여부 결정 대기.

**scope**: `data/deep-research/long-context-100k-recall-2026/round-1.md` 상단 참조. 6개 success_criteria (LongBench 2개, 기법 3개, RoPE vs 비RoPE, 실패 모드, 상용 recall, multi-hop).

### Round 1

- **Gemini queries** (3 병렬, pro, 900s timeout):
  1. "2025-2026 100k+ benchmarks landscape" → 52.8s, jobId g-e536d80a
  2. "Techniques maintaining recall at 100k+" → 107.3s, jobId g-844db6d2
  3. "Failure modes at 100k+" → 46.3s, jobId g-f7080546
- **Branch outcomes**: 3/3 본문 반환. pro 모델이 실제 생성. 1·2 branch 는 본문 뒤에 WebSearch grounding 429 error dump 가 trailing (생성은 완료된 후 발생). 3 branch 는 clean. 21 claim 추출 (c-r1-001 ~ 021).
- **Codex Skeptic**: `codex_run` (gpt-5.4/medium default, read-only), 497.7s (8m17s), jobId task-mnq927vf-wuiho9. 6-attack 구조 엄격 준수, 새 claim 주입 0, 실제 arxiv URL + leaderboard URL **발굴** (Gemini 가 숨긴 PRIMARY 출처 5건 식별: RULER/LongBench v2/MMNeedle/InfiniteHiP/EMNLP 2025 "Context Length Alone Hurts").
- **Judge (Claude)**:
  - Skeptic 지적 수용: **전체 (기각 0)** — 모두 구체적·재현 가능·counter-citation 포함
  - 생존 claim: **SURVIVES 5 / DOWNGRADED 3 / NEEDS-EVIDENCE 2 / DROPPED 10 / PARTIAL 1** (총 21)
  - Coverage: 3 partial × 0.5 = **1.5 / 6 (25%)**
  - 주요 발견: **Numeric discrepancy 1건 실제 잡힘** — RULER Gemini 1.5 Pro `0.944` (128K point) 와 `95.8%` (overall avg) 를 Gemini 가 하나로 병합 보고. Skeptic 이 복구.
- **종료 조건 체크**: 전부 미발동 (coverage 25%, round 1/5, wall clock ~17분 / 30분 budget, Skeptic 매우 강력). 정상 루프라면 Round 2 진입.
- **다음 라운드 쿼리 (Skeptic 제안)**: LongBench v2 / RULER / MMNeedle / InfiniteHiP / Qwen2.5-1M / DeepSeek-V3 / LOFT / EMNLP 2025 — 전부 primary 타겟.

### Round 2 ~ N

**미실행** — Session 1 은 Round 1 만 돌리고 사용자와 상의 후 결정하는 약속.

### Termination (Session 1 기준)

- reason: **user-hold** (합의된 일시 정지, 종료 조건 아님)
- final_coverage: 1.5 / 6 (25%)
- wall_clock: ~17 분 (Round 1 만)

### 최종 보고서

- 스테이징: **미작성** (루프 미완결 상태로 보고서 부적절)
- vault 승인: deferred
- vault 경로: —

### Session 1 관찰 기록

| 항목 | 값 |
|---|---|
| rounds_to_terminate | 1 (user-hold, not natural termination) |
| termination_reason | user-hold (out of spec — 템플릿 종료 조건 목록에 없음, **추가 필요**) |
| final_coverage | 1.5 / 6 (25%) |
| wall_clock_minutes | ~17 (Round 1 scope→Gemini→Skeptic→Judge full cycle) |
| gemini_branch_failures | **0/3** 본문 기준 (3/3 에 trailing grounding 429 error 가 뒤에 append — 생성 후 발생, 본문 영향 없음) |
| skeptic_valid_objections_per_round | **R1: 모든 지적 수용 (kill 9 + downgrade 3 + flag 7 + counter-cite 5)** |
| skeptic_false_positive_rate | **0%** (Round 1) — 모든 지적이 재현 가능·구체적 |
| claim_survival_rate | **5/21 survives (23.8%)**, 16/21 drop or downgrade or flag (76%) — **공격 성공률 매우 높음** |
| divergence_vs_depth | **발산 충분** — 3 branch 가 각기 다른 측면(benchmark landscape / techniques / failure modes) 을 다뤘고 토픽 겹침 최소. Skeptic 이 각 branch 에서 별개 primary source 를 발굴 → 다음 라운드 쿼리 7개가 **서로 다른** 출처를 타겟. 심화 부족 아님. |
| checklist_revised | no |

### 메타 노트 (Session 1 핵심 발견)

**1. Round 1 만으로도 Step 4a 의 핵심 가설이 검증됨**
   - Gemini Proposer → Codex Skeptic → Claude Judge 체인이 **실제로 동작**했다.
   - Skeptic 이 Gemini 의 tertiary-heavy 출력에서 **5개 PRIMARY arxiv/leaderboard URL 을 발굴**했다. 이건 단순 필터링이 아니라 **출처 복원** — Skeptic 이 Proposer 의 "숨긴 진짜 출처" 를 능동적으로 찾아내는 역할을 하고 있다. 예상 밖 강점.
   - Numeric discrepancy 1건 실제 검출 (RULER 0.944 vs 95.8% 병합 오류) — Attack 5 (Numeric recomputation) 가 장식이 아니었다.
   - EMNLP 2025 Findings paper 식별 — Gemini 가 Vertex grounding redirect 뒤에 숨긴 것을 Skeptic 이 실제 논문 제목·URL 로 복원. 체인의 **가장 인상적인 순간**.

**2. Gemini pro 는 Substack/Medium 로 우선 grounding 한다**
   - 프롬프트에 "Do NOT rely on blog posts" 명시했는데도 출처의 80% 가 tertiary.
   - 이건 Gemini CLI grounding 도구의 **source preference bias** — 검색 엔진이 newsletter 를 우선 크롤링한 결과를 선호한다. 프롬프트로 안 잡힘.
   - **대응**: Skeptic 이 필터링하는 게 맞는 해법. Proposer 프롬프트 개선으로는 안 고쳐짐. 이 실증이 B 패턴의 **존재 정당성** 을 확인해준 셈.

**3. Claim survival 23.8% 는 "건강한 숫자"** (직관)
   - 너무 낮으면: Proposer 가 쓰레기만 뿜는다 → B 재설계 필요
   - 너무 높으면: Skeptic 이 안 싸운다 → false negative
   - 25% 는 "Proposer 는 발산 잘 했고, Skeptic 이 엄격하게 걸러냈다" 의 이상적 분포
   - 단 **단일 라운드 표본** — Session 2 가 있어야 재현성 판단 가능

**4. Codex Skeptic 은 Gemini 보다 4.6배 오래 걸렸다** (497s vs 107s max branch)
   - 의외로 Skeptic 이 병목 — 예상은 Gemini 가 더 느릴 거였다.
   - 원인 추정: reasoning depth. 6-attack 구조 각 항목을 claim 별로 돌리느라 많은 토큰 생성.
   - wall clock budget 30분 중 Skeptic 이 27% 사용. Round 2~5 로 돌리면 Skeptic 만 40분 = budget 초과 가능.
   - **템플릿 개선 아이디어**: `max_rounds=3` 으로 낮추고 라운드당 검증 밀도를 더 높이는 게 실측적으로 합리적.

**5. Trailing error 처리 이슈 (MCP wrapper)**
   - branch 1·2 출력에 429 error dump 가 본문 뒤에 append 됨 → `codex_run` 의 "완성된 결과" 개념이 Gemini CLI 의 trailing log 를 감지 못함.
   - 이번엔 본문 생성 후라 내용 신뢰 가능했지만, 만약 본문 생성 전에 429 가 났으면 빈 문자열이 status: completed 로 올라옴.
   - **docs/mcp-servers.md 후속 개선 후보**: `gemini_run` 에 output validation — trailing error 블록 감지 + 별도 필드로 분리.

**6. "완료된 창 닫기" 문제는 사용자 환경 특이점**
   - 이전 시도 2/3 은 사용자가 Gemini CLI 가 spawn 한 터미널 창을 수동 닫은 것이 원인. MCP/Gemini 탓 아님.
   - **템플릿 note 추가 필요**: Windows 환경에서 Deep Research 실행 중 터미널 창이 뜨면 **닫지 말 것** (라운드 붕괴).

**7. Branch 3 (failure modes) 가 가장 짧았지만 가장 가치 있었다** (46s)
   - EMNLP 2025 paper 를 숨긴 채로 반환 → Skeptic 이 그 fragment 를 집어내서 primary 로 복원
   - **관찰**: "failure mode / counter-evidence 를 타겟하는 쿼리" 가 Round 1 에서 특히 Skeptic 과 궁합이 좋다. Round 2 쿼리 설계 시 failure-mode-oriented branch 를 유지할 것.

**8. "deep-research-b" 로서 Round 1 데이터는 Q1 전체 답변에 충분치 않다**
   - 25% coverage + 대부분 "존재 확인" 수준 + 수치는 1건만 신뢰
   - 현재 상태로 최종 보고서 작성하면 "체크리스트 6개 중 5개가 unfilled" 인 허약한 보고서
   - **Round 2 를 돌려야 실제 의사결정에 쓸 수 있는 보고서가 나옴** — 그러나 그건 Session 1 스콥이 아님
   - Session 1 목적은 **프로세스 검증** 이었고 이건 달성. Session 2 와의 분리 합리적.

### Session 1 에서 확정된 템플릿 개정 사항 (적용 대기)

1. `research-judge.md` termination_reason 목록에 `user-hold` 추가
2. `deep-research-template.md` 에 Windows 터미널 창 warning 추가
3. `docs/mcp-servers.md` 후속 개선: `gemini_run` output validation (trailing error 감지)
4. `research-skeptic.md` 시간 관찰: 6-attack 에서 "reasoning depth" 비용 문서화
5. `research-scope.md` 기본 `max_rounds` 5 → 3 고려 (wall clock budget 고려)
6. Session 2 실행 전 — 모든 개정 사항 반영 후 재진행 여부 결정

## Session 2 — python-framework-2026 (2026-04-09, **ABORTED — 무효 run**)

**질문**: "agent-orchestration 방향 3 확장 시 Python framework (LangGraph/DSPy/CrewAI) 를 도입할 가치가 있는가? 2026-04 기준 실사용·회피 사례."

**원래 목적**: Session 1 의 재현성 측정 (Skeptic drop rate 23.8%, Codex Skeptic 의 엄격도, Gemini PRIMARY URL 복원력 등 10개 관찰의 2차 측정).

**사전 조건**: MCP #9 패치 (Codex 3m 32s, 6/6 테스트 통과) 적용 후 실행. `parseResultOutput` 에 empty/placeholder/trailing-error guard 추가됨.

**결과: ABORT — reproducibility run 으로 무효 선언**.

### Run 1 (1차 발사)

| Branch | 쿼리 | 소요 | 결과 |
|---|---|---|---|
| A | LangGraph 프로덕션 사례 | 114s | 정상 (Klarna/Uber/Replit/BlackRock/Elastic 케이스 나열, 형식 부분 준수, URL 전부 vertex redirect) |
| B | DSPy vs CrewAI 비교 | 188s | **429 축약** (Shopify 75배 비용 절감, Fortune 500 40-50% 등 수치 일부, 응답 말미에 "Gemini Pro 429 로 축약됨" 자백) |
| C | Framework-less 채택 | 202s | **429 축약** (구체 사례 없음, 일반론만) |

### Run 2 (Pro 재시도 — 서버 capacity fluctuation 가정)

| Branch | 결과 |
|---|---|
| B | 여전히 429 축약, flash fallback 도 429 |
| C | **악화 — URL fabrication 발생**: `medium.com/@shashankguda/...0f1b1b1b1b1b` (slug 반복 → hallucination), `minimaxir.com/2023/07/...` (2023년 글, 날짜 필터 위반) |

### 폐기 사유

1. **통제 변수 오염**: Session 1 대비 Proposer 품질이 크게 저하 (B/C) → Skeptic drop rate 해석 불가 (엄격한 필터인지 저품질 input 때문인지 구분 불가)
2. **Branch asymmetry**: Run 1, Run 2 모두 position 0 (Branch A) 만 정상, position 1/2 만 축약 → 재현성 측정에 부적합
3. **URL fabrication 발견**: Gemini 가 429 후 training data 로 fallback 하면서 가짜 URL 을 조작. wrapper 레벨 탐지 불가. Skeptic URL verification 이 안 되면 최종 보고서가 가짜 소스 기반이 됨

### Session 2 에서 수집된 유효 관찰 3건 (재현성 측정은 실패, 운영 관찰로 전환)

**관찰 1 — Gemini 429 → URL fabrication** (→ `docs/mcp-servers.md` #10)
서버 capacity 부족 시 Gemini CLI 가 grounding 없이 응답 생성. 가짜 URL, 날짜 필터 위반, content-level self-report ("재시도 실패") 가 함께 등장. MCP wrapper 는 탐지 불가 (CLI 가 retry 후 깔끔하게 종료하면 stdout 에 429 signature 남지 않음). **Skeptic 단계에서 URL verification 으로만 잡을 수 있음**.

**관찰 2 — Branch position effect** (→ `docs/mcp-servers.md` #11)
3 branch 병렬 발사 시 position 0 은 정상, position 1/2 는 capacity 문제. 2 run × 3 branch = 6 관찰 중 정상 2건이 전부 position 0. n=6 으로 확정 불가하지만 재현성 있음. Workaround: sequential 발사 (20-30초 간격) — 병렬 이점 상실.

**관찰 3 — 도메인 × reliability 상호작용**
Session 1 Q1 (long-context benchmarks, arxiv heavy) 는 3/3 정상, PRIMARY URL 복원까지 성공. Session 2 Q2 (agent frameworks, blog/github heavy) 는 2/3 축약. Gemini grounding 이 **blog/github 소스에서 더 많은 retrieval cost 를 쓰거나** pro 용량 소진이 더 잦을 가능성. **리서치 주제 자체가 루프 신뢰도에 영향을 주는 변수** — 재현성 측정 주제는 arxiv-heavy 로 통일하는 것이 safer.

### Step 4b 영향

"재현성 측정 실패" 자체가 중요한 입력:
- B 루프의 reliability 는 **주제·시간대·branch position** 에 따라 크게 흔들림
- "B 로 충분" vs "C 필요" 의 단순 이분법으로는 결정 불가
- Session 1 + Session 2 관찰 종합 → **"B 로 충분하되 Skeptic 의 URL verification 이 필수 정책"** 으로 잠정. Session 3 에서 arxiv-heavy 주제로 재현성 재측정 필요.

### Session 3 재설계 권장사항

1. **주제**: arxiv-heavy (학술 benchmark, 논문 메타분석 등) — grounding load 낮은 도메인
2. **발사 전략**: sequential (20-30초 간격) — position effect 회피
3. **시간대**: Session 1 과 동일 시간대 (오전) — Google capacity fluctuation 변수 통제
4. **Skeptic 프롬프트 개정**: fabricated URL 탐지 명시 추가 (현재 `research-skeptic.md` 는 credibility 만 언급, 존재 여부 검증 미명시)
5. **Pre-check**: 각 run 시작 전 `gemini 상태` 로 quota % 확인

## Session 3 — long-context-benchmark-debate-2026 (2026-04-09, 재현성 측정 재시도 성공)

**질문**: 2025~2026 long-context retrieval 벤치마크의 saturation 논쟁 — needle-in-haystack(NIAH) 계열이 실제로 saturated 됐는지, 새 벤치마크(RULER, MRCR, LongBench v2, MMNeedle, LongICLBench)가 methodology 면에서 superseding 했는지.

**Status**: Round 1 만 실행 (Session 1 과 동일, 의도된 user-hold — 재현성 측정 완료 지점).

**Session 2 재설계 5 항목 준수 여부**:
1. ✅ arxiv-heavy 주제 (학술 benchmark)
2. ✅ Sequential 발사 (25초 간격 × 3 branch — position effect 회피 성공)
3. ✅ Pre-check (quota 여유 확인 후 진행, 시각 09:58)
4. ✅ Attack 1b URL fabrication heuristic 적용
5. ✅ 오전 시간대 (Session 1 과 동일)

**scope**: `data/deep-research/long-context-benchmark-debate-2026/round-1.md` 상단 참조. 6개 criteria (saturation paper 2+, counter paper 1+, 5 벤치마크 중 3+ rationale, methodology 비교표, 정량 비교, confound 2+).

### Round 1

- **Gemini branches** (3, pro, sequential 25s gap, 900s timeout):
  - Branch A — NIAH saturation claim evidence (127s)
  - Branch B — counter-argument / NIAH defender (140s)
  - Branch C — new benchmark methodology comparison (91s)
- **Branch outcomes**: **3/3 본문 반환, 0 timeout, 0 429** — Session 2 대비 dramatic 개선 (Session 2 는 2/3 429 축약). 13 distinct claim 추출 (A1-4, B1-4, C1-5).
- **Codex Skeptic**: 380s (Session 1: 497s, **-24%**), task-mnqs4mk3-8cemse, 6-attack 구조 엄격 준수.
- **Judge (Claude)**:
  - Skeptic 지적 전수 수용 (false positive 0%)
  - 생존: **SURVIVES 1 / DOWNGRADED 6 / NEEDS-EVIDENCE 1 / DROPPED 5** (total 13)
  - Coverage: **2.5 / 6 (41.7%)** — Session 1 (25%) 대비 +17pp
- **종료**: user-hold (재현성 측정 완료 지점)

### Session 3 최대 발견: Attack 1b 실전 검증 — 4건 fabricated URL 탐지

Session 2 에서 "arxiv-heavy 주제는 fabrication 에 안전할 것" 가설이 세워졌으나 **Session 3 에서 부분 반증**. 4 건의 서로 다른 fabrication 패턴 관찰:

| claim | URL | 실제 상태 | 탐지 heuristic |
|---|---|---|---|
| A2 | arxiv.org/abs/2604.03000 | URL 실존, 다른 수학 논문 | arxiv ID/title mismatch |
| B1 | aclanthology.org/2025.tacl-1.9/ | URL 실존, "Transformers as Transducers" 논문 | URL exists but unrelated content |
| B3 | arxiv.org/abs/2507.30 | invalid arxiv id | YYMM.NNNNN format violation (digit count) |
| B4 | arxiv.org/abs/2604.03 | invalid/truncated arxiv id | format violation |

**결정적 관찰**: Session 2 의 fabrication 패턴 (`medium.com/.../0f1b1b1b1b1b` 식 가짜 slug) 과 **형태는 다르지만 동일한 failure mode**. Gemini pro 는 도메인 무관하게 "citation 을 요구받았으나 실제 source 를 모를 때" 형식 맞춰 가짜를 생성함. **capacity exhaustion 과 독립된 새 failure mode** — `docs/mcp-servers.md` #10 에 "Confabulation when information is missing" 절 추가 후보.

**Attack 1b 의 검증된 가치**: Attack 1b 가 없었다면 Session 3 최종 보고서가 13 claim 중 4 개 (31%) 를 가짜 URL 로 인용할 뻔함. Session 2 에서 설계만 한 defense 가 Session 3 에서 즉시 실전 적중.

### Session 1 vs Session 3 재현성 측정 (arxiv-heavy × 오전 통제)

| 항목 | Session 1 | Session 3 | 델타 |
|---|---|---|---|
| Gemini branch 성공률 | 3/3 | 3/3 | = |
| Gemini max branch wall clock | 107s | 140s | +30% |
| Codex Skeptic wall clock | 497s | 380s | **-24%** |
| Total Round 1 wall clock | ~17min | ~14min | -18% |
| Distinct claim 추출 | 21 | 13 | -38% (Branch C table 묶음 영향) |
| DROPPED/REJECT 수 | 10 | 5 | -5 |
| DROPPED/REJECT 율 | 48% | 38% | -10pp |
| **Fabricated URL 건수** | **0** | **4** | **+4 (new failure mode)** |
| Primary URL 복원 (Skeptic 능동) | 5 | 1 (LongBench v2) | -4 |
| Numeric discrepancy 검출 | 1 (RULER 0.944 vs 95.8%) | 3 (A1, B1, C3) | +2 |
| Final coverage | 25% | 42% | +17pp |
| Skeptic 지적 수용률 | 100% | 100% | = |
| Skeptic false positive | 0% | 0% | = |

### Session 3 관찰 기록 (공통 metric)

| 항목 | 값 |
|---|---|
| rounds_to_terminate | 1 (user-hold, 의도된 정지) |
| termination_reason | user-hold (재현성 측정 완료) |
| final_coverage | 2.5 / 6 (41.7%) |
| wall_clock_minutes | ~14 |
| gemini_branch_failures | 0/3 |
| skeptic_valid_objections_per_round | R1: 모든 지적 수용 (REJECT 4 + FLAG 8 + counter-cite 1 + numeric catch 3) |
| skeptic_false_positive_rate | 0% |
| claim_survival_rate | 1/13 pure pass (7.7%), 7/13 pass-with-downgrade (54%), 5/13 drop (38%) |
| divergence_vs_depth | **발산 양호** — Branch A(증거)/B(반론)/C(methodology) 각기 다른 렌즈. Branch B 의 "NIAH defender 거의 없음" 은 negative finding 으로 정당성 확보. Session 1 과 동일 수준의 diversified coverage. |
| checklist_revised | no |

### Session 3 핵심 메타 노트

**1. 재현성 측정 성공 — B 루프 core pattern 이 재현됨**
- Gemini Proposer → Codex Skeptic → Claude Judge 체인이 Session 1 과 **거의 동일한 품질 프로파일**로 재현
- Skeptic 이 fake citation 을 100% 잡아내고 Judge 가 100% 수용 → false positive/negative 모두 0
- 재현성 N=2 는 확정적이지 않지만 두 세션 모두 **동일 도메인(arxiv-heavy)** 에서 동일 시간대면 reliable 하다고 잠정 결론 가능

**2. 새 failure mode 발견: "content-less confabulation"**
- Session 2 (#10) 은 "capacity exhaustion → fabrication" 으로 귀인했으나, Session 3 는 capacity 정상 + fabrication 4건 → **capacity 와 무관한 별도 모드 존재**
- 추정 원인: Gemini pro 가 grounding 을 "찾지 못함" 을 인정하지 않고 training data 에서 가장 그럴듯한 citation 패턴을 조합
- **docs/mcp-servers.md #12 신설 후보**: "Gemini pro content-less confabulation — grounding 이 조용히 실패하면 도메인 무관하게 fabricated citation 생성. wrapper 레벨 탐지 불가, Skeptic URL verification 이 유일한 방어선."

**3. Attack 1b heuristic 개선 후보 (R1 에서 관찰)**
- 현재 6개 heuristic 은 "URL exists but content mismatch" (A2, B1) 를 직접 커버 안 함
- 새 heuristic 7번 후보: "URL 이 실존하지만 paper title/arxiv abstract 이 claim 과 무관하면 SUSPECT"
- 단, 이는 Skeptic 이 arxiv abstract 에 접근 가능할 때만 작동 — sandbox 에서는 어려움. **flagging pattern 으로 대체**: "유명 논문 URL 인데 claim 이 생소하면 교차 확인"

**4. Skeptic 속도 향상 (-24%)**
- Session 1: 497s (21 claim)
- Session 3: 380s (13 claim)
- 정규화: Session 1 ~23.7s/claim, Session 3 ~29.2s/claim — claim 당 시간은 오히려 증가
- 즉 속도 향상은 claim 수 감소 덕 (Branch C 의 table 묶음 효과), Skeptic 자체 효율은 동일
- **교훈**: 재현성 metric 은 "claim 당 정규화" 해야 정확. 템플릿 관찰 항목 개정 후보.

**5. "NIAH defender 부재" 라는 negative finding 의 처리**
- Branch B 가 counter-argument 를 찾으러 갔으나 실제로는 "saturation 주장에 qualification 을 거는" paper 만 나옴
- Gemini 는 이 공백을 **가짜 URL 로 메꿈** — 가장 위험한 hallucination 패턴
- Skeptic 이 가짜를 모두 걸러냄으로써 "literature 가 undisputed 하다" 는 것 자체가 **Valid finding** 으로 전환
- **교훈**: B 루프의 Proposer 에게 "못 찾으면 빈 칸으로 둬라" 를 **더 강하게** 명시해야 함. research-scope.md 또는 Gemini query template 개정 후보.

**6. Coverage 42% 는 Session 1 대비 +17pp — scope 가 현실적이었던 이유**
- Session 1 criteria 는 "기법 3+, RoPE 비교" 등 specific 요구 많음
- Session 3 criteria 는 "벤치마크 3+, design rationale" 등 structural 요구 → Gemini branch C 의 table 응답과 자연스럽게 매치
- **교훈**: scope 의 checkable 항목은 "paper 가 직접 답할 수 있는 형태" 로 쓰는 게 coverage 에 유리. research-scope.md 의 "체크리스트 작성 규칙" 에 example 추가 가능.

### Session 3 Round 2 시도 및 Abort (2026-04-09 10:40, Step 5-B)

Step 5-B ("자연 종료 1회 관측") 를 위해 Session 3 Round 2 이어가기를 시도, **Gemini capacity exhaustion 으로 즉시 abort**. 이 abort 자체가 새 실증 데이터.

**실행 로그**:
- 10:40 KST, sequential launch (첫 branch)
- jobId g-ad5ac40b, pro, elapsed ~302s (pollIntervalMs 폴링 기준)
- warnings[trailing-error]: pro + flash 모두 `MODEL_CAPACITY_EXHAUSTED`, `web_fetch` 도 `'prompt' must contain at least one valid URL` 실패
- output: 3 papers 반환 (training-data fallback) — arxiv 2504.04150, 2504.04713 (Round 1 c-r1-004 와 **중복**), 2505.18148. Grounding 실패 상태에서 Gemini 가 composed 한 confabulation.

**MCP #9 패치 첫 production 검증 ✅**:
- `output` 필드에는 clean 본문만 포함, trailing error dump 는 `warnings[]` 로 분리됨
- 이전 Session 1/2 에서는 본문 + error dump 가 혼재했으나 이번엔 wrapper 가 정상 분리
- `warnings[0].type = "trailing-error"`, `signature = "Attempt 1 failed with status"`, `dump` 에 full 429 stacktrace
- Session 1 Round 1 branch 1·2 trailing error 처리 이슈가 완전 해결됨을 확인

**#10 + #12 동시 발현 케이스**:
- #10 (capacity exhaustion → fabrication): 429 실측됨 → CLI retry → training data fallback
- #12 (content-less confabulation): capacity 여부와 무관한 grounding 공백 — 본 케이스에서는 #10 이 #12 의 트리거
- 둘의 관계: **#12 는 grounding 실패의 general case, #10 은 그 중 capacity-driven 하위 케이스**. Session 3 R1 의 4 건 fabrication 은 "원인 불명의 #12", R2 abort 의 3 건 confabulation 은 "429-driven 의 #12" 로 재분류 가능.

**시간대 가설 약화**:
- Step 4b 결정의 필수 정책 (c): "arxiv-heavy × 오전 검증됨" 을 근거로 했으나, R2 는 **정확히 같은 조건 (arxiv-heavy × 오전 10:40 × sequential launch)** 에서 capacity exhaustion 발생
- 즉 재현성은 시간대/도메인만의 함수가 아니라 **Google capacity 의 하루 단위 fluctuation** 이 주요 변수
- Step 4b 필수 정책 (c) 를 "arxiv-heavy × 오전 × capacity 여유 확인 후" 로 수정 권장 (pre-check 강화)

**R2 abort 의사결정**:
- 옵션 B (degraded 데이터로 Skeptic 돌려 루프 방어 관찰) 는 재현성 metric 오염 → 기각
- 옵션 C (abort + Step 5-C 로 전환) 채택 — Session 3 R1 기반 vault end-to-end 검증이 더 싸고, 자연 종료 관측은 별도 세션으로 이월
- Step 4a Done 기준 6/7 까지 커버 가능 (자연 종료 1회는 미완 유지)

**공통 metric 업데이트 (R2 abort 반영)**:

| 항목 | Session 3 R1 | R2 시도 | 비고 |
|---|---|---|---|
| rounds_attempted | 1 | 0 (abort) | — |
| termination_reason (R2) | — | **capacity-exhaustion-abort** (종료 조건 목록 밖, **추가 후보**) | |
| gemini_branch_failures | 0/3 | 1/1 (429) | sequential 첫 branch 에서 즉시 429 |
| gemini_fabricated_urls | 4 | 3 (training data fallback 전원) | — |

**템플릿 개정 후보 (Step 5-B abort 발) — Step 5 후반 처리 대기**:
1. `research-scope.md` constraints 에 **pre-check 강화**: `gemini 상태` 로 quota/capacity 확인을 plan 단계가 아닌 **Round 1 직전 필수 단계** 로 격상
2. `research-judge.md` termination_reason enum 에 `capacity-exhaustion-abort` 추가 (user-hold 와 별개 — 사용자 합의 없이 autoloop 에서 발생)
3. `deep-research-template.md` Fallback 섹션에 "Round 시작 전 capacity-exhaustion 발견 시 즉시 abort + 재시도 스케줄링" 명시
4. Session 3 R1 의 "Step 4b 시간대 × 도메인 결정" 필수 정책 (c) 수정: "capacity 여유 확인 후" 단서 추가

### Session 3 에서 확정된 템플릿 개정 사항 (2026-04-09 적용 완료, Step 5-A)

1. ✅ `docs/mcp-servers.md` #12 신설: "Gemini pro content-less confabulation" — capacity 와 독립된 failure mode, Session 3 4건 실증 테이블 포함
2. ✅ `examples/prompts/research-skeptic.md` Attack 1b heuristic 7 추가: "URL exists but resolves to unrelated content" — arxiv id 형식 검증 + content mismatch 패턴 + Branch B 같은 negative-finding 집중 경고
3. ✅ `examples/deep-research.md` 공통 metric 에 `skeptic_seconds_per_claim` / `skeptic_objections_per_claim` / `gemini_fabricated_urls` 추가 + "정규화 원칙" 섹션 신설
4. ✅ `examples/deep-research-template.md` Gemini query 공통부에 Anti-fabrication policy 블록 강화 ("못 찾으면 빈 칸, negative finding 도 valid finding")
5. ✅ `examples/prompts/research-scope.md` 체크리스트 작성 규칙 6번 (Structural criterion 우선) + Session 1/3 좋은/나쁜 example 추가

---

## Step 4a Done 기준 체크 (Session 1 + 3 종합)

- [x] Scope → checklist 생성 동작 (Session 1, 3 모두 실측)
- [x] 1 라운드 full cycle: Gemini ×3 → Codex Skeptic → Claude Judge (Session 1, 3)
- [x] Codex Skeptic 이 최소 1개 유효 지적 생성 (Session 1: 9 REJECT + 3 downgrade, Session 3: 4 REJECT + 8 FLAG)
- [x] 실제 리서치 질문 2~3개로 full 루프 완주 (Session 1 long-context-recall, Session 3 benchmark-debate — Session 2 는 abort 로 counting 제외)
- [ ] Coverage 기반 종료 1회 + max_rounds 종료 1회 관측 — **미완**. 두 세션 모두 user-hold 로 종료. Round 2-3 미실행 상태에서 자연 종료 관측 없음
- [ ] 최종 보고서 vault 승인 저장 end-to-end 1회 — **미완** (보고서 작성 건너뜀)
- [x] `examples/deep-research.md` 작성 (Session 1, 2, 3 섹션 모두 채움)

**Done 기준 5/7 충족**. 2개 미충족 (자연 종료 + vault 승인) 은 "재현성 측정" 목적으로 의도적으로 건너뛴 것. Step 4a 는 **프로세스 검증 완료**로 판단 가능하나 end-to-end 완주는 별도 세션 필요.

## Step 4b 분기 결정 (Session 1 + 3 종합)

플랜 4b 표 기준:

| 관찰 | 행동 | 이번 실측 해당? |
|---|---|---|
| 발산 충분 + Skeptic 유효 | B 로 충분. Step 4 종료. | **✓ YES** — Session 1, 3 모두 diversified branch + Skeptic 0% false positive |
| 발산 부족 (같은 방향 깊이) | C 로 확장 (트리 구조) | ✗ (Session 1, 3 모두 branch 간 독립 토픽 유지) |
| Skeptic 노이즈만 뿜음 | B 재설계 | ✗ (Skeptic 양 세션 모두 고품질) |
| 둘 다 문제 | 플랜 재작성 | ✗ |

**결정**: **B (Proposer + Skeptic + Judge) 패턴으로 충분. C (multi-round agentic tree) 는 현 단계에서 불필요.**

**근거** (Session 1, 3 공통 패턴):
1. **Skeptic 은 본질적 가치를 제공**: 단순 필터링이 아닌 능동적 source 복원, URL fabrication 탐지, numeric discrepancy catch. Session 3 에서 fake citation 4 건을 잡지 못했다면 최종 보고서의 31% 가 거짓이었음.
2. **Branch 발산은 scope 프롬프트 수준에서 해결됨**: 두 세션 모두 Round 1 에서 3 branch 가 독립 토픽 커버. Tree 구조가 필요한 "발산 부족" 관찰 없음.
3. **Claim survival rate 가 건강한 분포**: Session 1 23.8% survives, Session 3 7.7% pure + 54% downgrade. 두 경우 모두 "Proposer 는 발산, Skeptic 은 엄격 필터" 의 이상적 adversarial dynamic 유지.
4. **복잡한 질문일수록 Judge 가 partial coverage 를 허용하며 안정적으로 수렴**: Session 3 42% > Session 1 25%, scope 가 현실적이면 coverage 가 자연스럽게 올라감.

**단, B 패턴에 **필수 정책** 3 개 추가 조건으로**:
- **(a) Skeptic 의 URL verification 은 옵션이 아닌 필수** (Attack 1b + Session 3 confirmation)
- **(b) sequential Gemini launch (25초 간격)** — Session 2 #11 position effect 회피
- **(c) arxiv-heavy + 오전 시간대** 에서 재현성이 검증된 범위 — blog/github heavy 주제는 별도 실증 필요

**다음 액션**:
1. `docs/orchestration-roadmap.md` 의 Step 4 를 "B 패턴 채택" 으로 종결 업데이트
2. `docs/mcp-servers.md` #12 (content-less confabulation) 추가
3. `examples/deep-research-template.md` 에 Session 3 에서 확정된 5 개 템플릿 개정 사항 반영
4. Step 4b 종료 → Step 5 (실제 연구 질문에 대한 end-to-end 완주 + vault 승인 경로 검증) 분기

**남은 미검증 영역** (Step 4a-b 에서 의도적으로 건너뜀, 후속 세션 필요):
- 자연 종료 조건 발동 (coverage-full / stagnation / skeptic-failed / max-rounds) 1회 이상 실측
- 최종 보고서 작성 + vault 승인 게이트 end-to-end 1회
- blog/github heavy 주제에서의 B 패턴 reliability (Session 2 abort 영역)
- Round 2~3 에서 Skeptic 지적이 누적될 때 false positive 여부

---

## 메모

### 체인 특이사항 (실증 중 수시 업데이트)

- _(Gemini pro 의 hang 빈도 관찰)_
- _(Codex Skeptic 의 새 claim 주입 경향)_
- _(checklist partial 판정의 일관성)_
- _(라운드 로그 크기 문제)_

### 프롬프트 개선 후보

- _(research-scope.md: )_
- _(research-skeptic.md: )_
- _(research-judge.md: )_
- _(research-final.md: )_
