# Research Scope Prompt — Claude 내부용

> Deep Research B 루프의 0단계. Claude 가 **직접** 실행한다 (Gemini/Codex 위임 아님).
> 입력: 사용자 원질문 한 줄~한 단락. 출력: 구조화된 scope + success_criteria checklist.

## 목적

원질문을 그대로 Gemini 에 던지면 발산이 제어되지 않는다. Scope 단계에서:
1. 질문의 실제 의도를 5W1H 로 분해
2. "무엇을 알면 답이라 할 수 있는가" = success_criteria 를 명시적 checklist 로 고정
3. 이 checklist 가 종료 판정 + 최종 보고서 목차 역할을 **동시에** 한다

체크리스트가 없으면 종료 조건이 `max_rounds` 뿐이라 루프가 시간 낭비가 된다.

## 입력 형식

사용자 원질문 + (선택) 시간/예산/깊이 힌트.

## Claude 가 생성할 출력 (YAML 블록)

```yaml
question: "<원질문 한 줄로 재진술>"

intent:
  who: "<결과를 쓸 사람 / 대상 독자>"
  what: "<구체적으로 알고 싶은 것 — 개념? 수치? 비교? 사례? 결정 근거?>"
  when: "<시간 범위 — 최신? 역사적 흐름? 특정 기간?>"
  where: "<도메인/지역/산업 범위>"
  why: "<이 답으로 내릴 결정 또는 해결할 문제>"
  how: "<원하는 답 형식 — 비교표? 권장안? 리스크 목록? 인용 목록?>"

success_criteria:
  # 3~7 개. 각 항목은 "checkable" — 라운드 끝에 yes/no 로 판정 가능해야 한다.
  # 나쁜 예: "충분한 조사", "주요 내용 커버"
  # 좋은 예: "기법 최소 3개 이름+논문/발표년도", "2025-2026 벤치마크 1개 이상"
  - "<항목 1>"
  - "<항목 2>"
  - ...

out_of_scope:
  # 명시적으로 제외. 발산 제어용.
  - "<제외 1>"

constraints:
  max_rounds: 3            # 기본값 3. 4a Session 1 실측: Codex Skeptic 이 라운드당 8분+ 소요 → 5 는 30분 budget 초과 위험. 질문이 단순하면 2, 복잡하면 최대 5.
  wall_clock_minutes: 30   # 하드 캡 60
  parallel_gemini: 3
  gemini_model: "pro"      # Deep Research 는 기본 pro
  gemini_timeout_ms: 900000
  pre_check_required: true # **필수** — Round 1 직전 gemini_run 으로 pro 경량 probe 1회. MODEL_CAPACITY_EXHAUSTED 면 abort + 재시도 스케줄링 (Session 3 R2 abort 2026-04-09 교훈).

slug: "<kebab-case-slug — 파일명/디렉토리명 용, 30자 이내>"
```

## 체크리스트 작성 규칙

1. **검증 가능성**: 라운드 말에 Judge 가 "이 항목이 채워졌나?" 를 이진 판단할 수 있어야 한다.
2. **구체성**: "벤치마크 언급" ❌ → "2025 이후 벤치마크 1개 이상, 점수 수치 포함" ✅
3. **독립성**: 항목끼리 중복되면 Coverage % 가 왜곡됨.
4. **현실성**: "모든 논문 인용" 같은 항목은 달성 불가 → 루프가 영원히 안 멈춤.
5. **항목 수 3~7**: 3 미만은 너무 느슨, 7 초과는 너무 엄격.
6. **Structural criterion 우선** (2026-04-09 Session 3 교훈): "specific fact 를 찾아라" 보다 "X 개 후보를 구조적으로 비교하라" 형태가 Gemini Proposer 의 table-style 응답과 매치가 잘 됨. Coverage 가 자연스럽게 올라간다.
   - Session 1 specific-fact 스타일 (25% coverage): "100k+ 에서 recall 유지하는 기법 3+개 이름+논문"
   - Session 3 structural 스타일 (42% coverage): "5 벤치마크 중 3+개의 methodology rationale + 비교표"
   - **차이**: specific-fact 는 Proposer 가 "못 찾으면 빈 칸" 이 되지만, structural 은 Proposer 가 발견한 N 개를 나열만 해도 partial credit 가능.

### Example — 좋은 checklist (Session 3 스타일, 벤치마크-친화적)

```yaml
question: "2025-2026 long-context retrieval 벤치마크의 saturation 논쟁 현황"

success_criteria:
  # 1. Structural: N 개 후보 나열 (Gemini table 응답과 매치)
  - "saturation 주장 paper 2+ 개 (제목, 저자, 발표년도, 핵심 claim)"
  - "saturation 반대 또는 qualification paper 1+ 개 OR 'no counter-paper found' negative finding"
  # 2. Structural: 비교 rubric
  - "RULER / MRCR / LongBench v2 / MMNeedle / LongICLBench 중 3+ 개의 methodology rationale"
  # 3. Structural: 차원 간 비교표
  - "위 벤치마크들의 정량 비교표 (task type, 길이 범위, 평가 metric 각 1 셀 이상)"
  # 4. Structural: confound 나열
  - "saturation 주장의 confound 2+ 개 (예: training data leak, prompt template effect)"
  # 5. 상위 결정용 요약
  - "NIAH 계열이 실제로 superseded 됐는지 Judge 가 1-line verdict 로 요약 가능"
```

### Example — 나쁜 checklist (specific-fact 스타일, 종료 어려움)

```yaml
success_criteria:
  - "RULER 에서 Gemini 1.5 Pro 의 128K recall 점수"         # 단일 숫자 의존
  - "100k+ 에서 recall 유지 기법의 구현 세부사항"            # Gemini 가 vendor docs 없으면 못 채움
  - "RoPE vs non-RoPE 방식의 empirical 비교"                 # 있을 수도, 없을 수도 — binary 판정 어려움
```

두 example 모두 실제 Session 1/3 에서 실행한 checklist 다. 전자는 Session 3 에서 coverage 42%, 후자는 Session 1 에서 coverage 25% 로 끝났다. 같은 라운드 수, 같은 Proposer 품질이었지만 **scope 가 Proposer 능력과 매치되는가** 가 coverage 를 17pp 바꿨다.

## 체크리스트 수정 라운드 (1회 허용)

Round 1 후 Judge 단계에서 "체크리스트가 질문과 안 맞음" 이 명확하면, Claude 가 **1회 한정** 체크리스트를 재작성할 수 있다. 재작성 사유를 로그에 기록. 2회 이상은 금지 (goal-post 이동).

## 제출 전 체크

- [ ] success_criteria 각 항목이 "yes/no 로 판단 가능한가?"
- [ ] out_of_scope 가 최소 1개 이상 (발산 제어)
- [ ] slug 가 파일명으로 쓸 수 있는가
- [ ] constraints 가 플랜 기본값에서 벗어났다면 그 이유가 질문 안에 있는가
- [ ] **Gemini pro capacity pre-check 통과 (Round 1 직전 필수)** — scope 승인 후 Round 1 발사 전에 `gemini_run(model="pro", prompt="<10토큰 probe>")` 1회 실행, `MODEL_CAPACITY_EXHAUSTED` 없으면 진행, 있으면 abort + 사용자에게 재시도 시점 보고 (2026-04-09 Session 3 R2 교훈 — 오전 arxiv-heavy 에서도 pro capacity 소진 발생)
