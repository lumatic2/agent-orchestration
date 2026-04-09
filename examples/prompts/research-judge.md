# Claude Judge Prompt — 라운드 판정 규칙

> Deep Research B 루프의 수렴 단계. Claude 가 **직접** 수행한다. Gemini/Codex 위임 아님.
> 입력: (1) 해당 라운드의 Gemini Proposer 출력들, (2) Codex Skeptic 출력, (3) scope 단계 success_criteria. 출력: 살아남은 claim 집합 + coverage 업데이트 + 다음 라운드 쿼리 (또는 종료 선언).

## 단계

### 1. Skeptic 지적 필터링

Skeptic 의 각 지적을 다음 수용 기준으로 분류:

- ✅ **수용**:
  - Red flag 중 source bucket 이 TERTIARY/UNSUPPORTED 인 HIGH-impact claim
  - Counter-evidence 가 구체적 출처·수치와 함께 제시된 경우
  - Methodology hole 이 재현 가능한 수치 지적 (예: "샘플 n=8", "1개 하드웨어만 사용")
  - Numeric recomputation 에서 실제 불일치 발견
- ❌ **기각**:
  - "might be biased", "could be outdated" 같은 hedge 표현
  - 메타 비판 ("더 많은 소스가 필요하다") — 다음 라운드 쿼리로만 반영, claim 은 유지
  - Skeptic 이 뿜어낸 새로운 주장 (Skeptic 은 critic, not researcher)
  - 원칙론 ("should cite more papers") 이고 구체 결함이 없는 경우

수용된 지적을 표로 정리 — 이게 로그에 남는 핵심 자산.

### 2. Claim 생존 판정

Gemini 가 제출한 각 claim 을 다음 중 하나로 라벨링:

- **SURVIVES** — Skeptic 이 공격 안 했거나 공격이 기각됨
- **DROPPED** — 수용된 지적이 claim 을 무효화
- **DOWNGRADED** — claim 자체는 살지만 신뢰도 라벨 추가 ("단일 tertiary source", "미검증 수치")
- **NEEDS-EVIDENCE** — claim 은 흥미롭지만 출처 보강 필요 → 다음 라운드 쿼리 타겟

### 3. Coverage 업데이트

Scope 의 `success_criteria` 각 항목을 돌면서:

- 이 라운드의 **SURVIVES** claim 집합이 해당 항목을 채우는가? yes/no
- 누적 coverage 계산 (이전 라운드 포함): `filled / total`

Coverage 테이블 형식 (라운드 로그에 그대로 append):

```markdown
| criterion | filled? | evidence (claim_id) | round_filled |
|---|---|---|---|
| 기법 최소 3개 이름+연도 | ✓ | c-r2-003, c-r2-007, c-r2-011 | R2 |
| LoRA 정량 비교 | ✗ | — | — |
| 2025-2026 벤치마크 | partial | c-r1-015 (1개만) | R1 |
| 상용 채택 사례 | ✗ | — | — |
```

**partial** 허용 — 항목이 요구하는 증거 개수가 절반 이상 채워진 경우. 최종 coverage 계산 시 partial = 0.5 로 환산.

### 4. 종료 조건 체크 (OR)

- [ ] Coverage 100% (모든 항목 ✓)
- [ ] Coverage 증가량 2 라운드 연속 0 (정체)
- [ ] rounds_completed >= max_rounds
- [ ] Skeptic 이 유효 반박 2 라운드 연속 0 개 (비평 실패)
- [ ] wall clock 도달 (scope constraints 의 `wall_clock_minutes`, 하드 캡 60분)
- [ ] `data/deep-research/{slug}/STOP` 파일 존재 (사용자 수동 중단)
- [ ] `user-hold` — 사용자가 대화 중 루프 일시정지 요청 (자연 종료 아님, 재개 가능)
- [ ] `capacity-exhaustion-abort` — Round 시작 전 pre-check 또는 Round 중간에 Gemini pro `MODEL_CAPACITY_EXHAUSTED` 연속 발생 (자연 종료 아님, autoloop 가 사용자 합의 없이 발동 — 재시도 스케줄링 필요)

하나라도 만족 → 종료 선언 → 5단계로.

> `user-hold` 와 `capacity-exhaustion-abort` 는 루프 "종료" 가 아니라 **일시 정지 마커**. 최종 보고서 작성은 건너뛰고 라운드 로그까지만 보존. 재개 시 coverage 상태 그대로 이어감. `capacity-exhaustion-abort` 의 경우 재개 전 pro capacity pre-check 통과가 선행 조건.
아니면 → 6단계 (다음 라운드 쿼리) 로.

### 5. 종료 선언 (해당 시)

라운드 로그에 명시:

```markdown
## Termination — Round N

- reason: <coverage-full | stagnation | max-rounds | skeptic-failed | wall-clock | stop-file | user-hold | capacity-exhaustion-abort>
- final_coverage: X / Y (Z%)
- total_rounds: N
- total_wall_clock: M minutes
- unfilled_criteria: [...]  # 보고서에 "알려지지 않은 것" 섹션으로 명시
```

→ `research-final.md` 템플릿으로 최종 보고서 작성 단계 진입.

### 6. 다음 라운드 쿼리 생성 (계속하는 경우)

`parallel_gemini` (기본 3) 개의 Gemini 쿼리를 만든다. 규칙:

- 각 쿼리는 **서로 다른 unfilled 또는 partial criterion 을 타겟**. 중복 금지.
- `NEEDS-EVIDENCE` claim 이 있으면 그 중 가장 중요한 것을 1 개 쿼리로.
- 쿼리 문체는 검색용이 아니라 Gemini pro 에 맞게: "리서치 주제 + 원하는 출처 유형 + 제외 조건" 명시.
- 각 쿼리는 독립적이어야 함 (병렬 실행).

쿼리 템플릿:
```
Research target: <unfilled criterion>
Context from prior rounds: <1~2 line summary of what was already found>
Required sources: <primary papers / benchmarks / vendor docs / case studies>
Explicitly exclude: <what NOT to return — e.g., "no blog posts", "no marketing">
Time range: <2024~2026 등>
Output format: 각 claim 에 출처 URL + 발표년도 포함
```

3 개 쿼리를 **병렬**로 `gemini_run(model="pro", timeoutMs=900000)` 호출.

### 7. 라운드 로그 기록

`data/deep-research/{slug}/round-N.md` 에 다음을 append:

- Round number, timestamp, elapsed wall clock
- 각 Gemini branch 원본 출력 (요약 아님, 원문)
- Codex Skeptic 원본 출력
- 수용된 지적 표
- Claim 생존 테이블 (id | label | reason)
- Coverage 테이블 (누적)
- 종료 조건 체크 결과
- 다음 라운드 쿼리 3개 (또는 종료 선언)

로그는 debug + 최종 보고서 증거 인덱스 + 4b 관찰 기록 3가지 역할.

## 판정 시 주의

- **Skeptic 은 절대 무비판 수용하지 마라**. Step 2 의 교훈: adversarial 출력은 false positive 가 섞인다. 이번 체인에서는 "재현 가능한 수치 지적" 만 수용.
- **Gemini 출력도 무비판 수용 금지**. Gemini 가 tertiary 출처만 반환했으면 그 라운드의 Coverage 증가는 보수적으로 잡아라. partial 표시.
- **체크리스트 재작성은 최대 1회 (Round 1 이후)**. 그 이상은 goal-post 이동.
- **Claude 가 스스로 claim 을 만들지 마라**. Judge 는 필터이지 생성자가 아니다. 모르는 건 unfilled 로 남기고 최종 보고서에 "알려지지 않은 것" 섹션으로.
