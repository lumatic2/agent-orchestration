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

slug: "<kebab-case-slug — 파일명/디렉토리명 용, 30자 이내>"
```

## 체크리스트 작성 규칙

1. **검증 가능성**: 라운드 말에 Judge 가 "이 항목이 채워졌나?" 를 이진 판단할 수 있어야 한다.
2. **구체성**: "벤치마크 언급" ❌ → "2025 이후 벤치마크 1개 이상, 점수 수치 포함" ✅
3. **독립성**: 항목끼리 중복되면 Coverage % 가 왜곡됨.
4. **현실성**: "모든 논문 인용" 같은 항목은 달성 불가 → 루프가 영원히 안 멈춤.
5. **항목 수 3~7**: 3 미만은 너무 느슨, 7 초과는 너무 엄격.

## 체크리스트 수정 라운드 (1회 허용)

Round 1 후 Judge 단계에서 "체크리스트가 질문과 안 맞음" 이 명확하면, Claude 가 **1회 한정** 체크리스트를 재작성할 수 있다. 재작성 사유를 로그에 기록. 2회 이상은 금지 (goal-post 이동).

## 제출 전 체크

- [ ] success_criteria 각 항목이 "yes/no 로 판단 가능한가?"
- [ ] out_of_scope 가 최소 1개 이상 (발산 제어)
- [ ] slug 가 파일명으로 쓸 수 있는가
- [ ] constraints 가 플랜 기본값에서 벗어났다면 그 이유가 질문 안에 있는가
