# /gs — gstack 진입점 라우터. 스킬 이름이 기억 안 날 때 이것만 실행.

$ARGUMENTS 가 있으면 Step 1로, 없으면 Step 2로 간다.

---

### Step 1: 인자 패스스루 (빠른 라우팅)

$ARGUMENTS 텍스트를 분석하여 아래 키워드 매핑에서 가장 적합한 스킬을 **1개** 찾아라.
매칭되면 질문 없이 바로 Step 3으로 이동.
매칭 안 되면 Step 2로.

**키워드 → 스킬 매핑:**

| 키워드 (부분 일치) | 스킬 |
|---|---|
| 아이디어, 브레인스토밍, 기획 | `/office-hours` |
| 리뷰 파이프라인, 전체 리뷰, autoplan | `/autoplan` |
| 엔지니어링, 아키텍처, eng | `/plan-eng-review` |
| 전략, 스코프, ceo | `/plan-ceo-review` |
| 코드 구현, 구현, 빌드, codex 위임 | Codex 위임 |
| PR, ship | `/ship` |
| 디자인 시스템, 브랜딩 | `/design-consultation` |
| 리뷰, 코드 리뷰, 검토 | `/review` |
| 세컨드 오피니언, codex 리뷰 | `/codex` |
| QA, 테스트, 품질 | `/qa` |
| 보안, 감사, cso | `/cso` |
| 버그, 디버깅, 에러 | `/investigate` |
| 배포, deploy, land | `/land-and-deploy` |
| 회고, retro | `/retro` |
| 문서, docs | `/document-release` |

---

### Step 2: 스킬 추천 (1회 질문)

git 체크 없이 바로 AskUserQuestion 1회. 대표 스킬 4개 고정:

> 뭐 할까요?

- A) 아이디어/기획 — `/office-hours`
- B) 코드 구현 (Codex 위임) — `orchestrate.sh codex`
- C) 코드 리뷰 — `/review`
- D) 버그 디버깅 — `/investigate`

사용자가 "Other" 선택 시 자유 텍스트를 분석하여 키워드 매핑 적용 후 재추천.

---

### Step 3: 안내 출력

선택된 스킬의 **커맨드와 한 줄 설명**, 그리고 **같은 카테고리의 관련 스킬**을 함께 보여줘라:

```
👉 `/review` 를 입력하세요 — PR diff 분석: SQL 안전성·LLM 신뢰경계·레이스컨디션

   같은 카테고리 (검증·품질):
   /codex    — Codex 독립 리뷰 (cross-model 검증)
   /qa       — 웹앱 QA 테스트 + 버그 자동 수정
   /cso      — 보안 감사 (OWASP, STRIDE)
```

**카테고리 매핑:**

| 카테고리 | 스킬 목록 |
|---|---|
| 기획·설계 | `/office-hours`, `/autoplan`, `/plan-eng-review`, `/plan-ceo-review`, `/design-consultation` |
| 구현·빌드 | Codex 위임, `/ship` |
| 검증·품질 | `/review`, `/codex`, `/qa`, `/cso` |
| 운영·회고 | `/investigate`, `/land-and-deploy`, `/retro`, `/document-release` |

추천된 스킬은 목록에서 제외하고 나머지만 "같은 카테고리"로 표시.

스킬을 Skill 도구로 직접 실행하지 않는다.
사용자가 직접 입력하도록 안내만 한다. (컨텍스트 절약)

**예외 — Codex 위임만 직접 실행:**
"어떤 작업을 위임할까요?" 라고 물은 뒤
`orchestrate.sh codex "작업내용" name` 형태로 Bash 실행.

---

## 전체 스킬 목록 (참고용)

```
기획·설계:
  /office-hours       — 아이디어·기획 브레인스토밍
  /autoplan           — 전체 리뷰 파이프라인 (CEO+디자인+엔지니어링)
  /plan-eng-review    — 엔지니어링 계획 검토
  /plan-ceo-review    — 전략·스코프 검토
  /design-consultation — 디자인 시스템 생성

구현·빌드:
  orchestrate.sh codex — 코드 구현 위임
  /ship               — PR 생성

검증·품질:
  /review             — PR 코드 리뷰
  /codex              — Codex 독립 리뷰
  /qa                 — 웹앱 QA 테스트
  /cso                — 보안 감사

운영·회고:
  /investigate        — 버그 디버깅
  /land-and-deploy    — 배포 + 검증
  /retro              — 주간 회고
  /document-release   — 문서 업데이트
```
