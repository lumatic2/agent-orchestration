# 멀티 에이전트 협업 아키텍처 v3

## 1. 목적

이 설계안은 `agent-orchestration` 저장소의 멀티 에이전트 시스템을 "문서상 역할 분리"에서 "런타임에서 강제되는 협업 프로토콜"로 끌어올리는 것을 목표로 한다.

핵심 변화는 세 가지다.

1. `queue/`를 단순 디스패치 폴더가 아니라 `Task Packet`의 단일 진실 소스로 바꾼다.
2. Claude, Codex, Gemini의 협업을 자유형 프롬프트 전달이 아니라 typed artifact 기반 핸드오프로 바꾼다.
3. 실패 복구를 단순 fallback 체인에서 failure class + degraded mode 기반 운영으로 바꾼다.

이 문서는 현재 저장소 구조를 기준으로 태스크 분배 전략, 협업 프로토콜, 상태 모델, 실패 복구, 병렬 실행, 마이그레이션 순서를 정의하는 v3 런타임 스펙이다.

---

## 2. 현재 구조 진단

### 유지할 강점

- `scripts/orchestrate.sh`가 이미 영속 큐, fallback, `--boot`, `--resume`, `--status`, `--cost`를 제공한다.
- `templates/task_brief.md`가 `Scope`, `Context Budget`, `Stop Triggers`를 강제한다.
- `agent_config.yaml`이 모델 tier, reasoning, fallback chain의 단일 진실 소스 역할을 한다.
- `scripts/run_blueprint.py`와 `blueprints/`가 순차 파이프라인 자동화를 이미 시작했다.
- Claude, Codex, Gemini의 역할 분리는 문서와 어댑터에 일관되게 반영돼 있다.

### 현재 한계

1. 개념 설계와 런타임이 분리돼 있다.
   - 현재 큐는 사실상 `meta.json + brief.md + progress.md + result.md`만 가진다.
   - v2 문서의 richer state, typed artifact, recovery record가 실제 저장 구조에 반영되지 않았다.

2. 핸드오프가 여전히 "stdout 파이핑"이다.
   - `scripts/run_blueprint.py`는 `{{steps.research.result}}`를 다음 step 프롬프트에 그대로 삽입한다.
   - 이는 구조화된 인수인계가 아니라 긴 텍스트 복사이므로 재사용성과 복구성이 낮다.

3. 상태가 한 필드에 과적재돼 있다.
   - 현재 핵심 상태는 `pending / dispatched / queued / completed` 중심이다.
   - transport 상태, 실제 작업 상태, 비즈니스 outcome을 구분하지 못한다.

4. `--resume`이 재생성 semantics를 모른다.
   - `pending`, `queued`, `dispatched`를 모두 다시 실행 대상으로 보지만 claim/lock이 없다.
   - 여러 세션이나 여러 러너가 있으면 중복 실행과 충돌이 발생할 수 있다.

5. 라우팅 로직이 Claude의 암묵지에 의존한다.
   - `agent_config.yaml`은 모델 선택에는 강하지만, risk gate, degraded mode, failure-class 정책은 담고 있지 않다.

6. `--chain`과 `blueprints/`가 큐 상태 모델을 우회한다.
   - 체인과 블루프린트는 멀티스텝 워크플로우지만, 현재는 하나의 통합 state machine 아래로 들어오지 않는다.

---

## 3. v3 설계 원칙

### 원칙 A. Claude는 Control Plane이다

- Claude는 intake, 분해, 계약, 승인, 통합, 메모리 업데이트만 담당한다.
- 대규모 구현 루프와 대규모 리서치는 직접 수행하지 않는다.

### 원칙 B. Gemini는 외부 불확실성만 제거한다

- 외부 문서, 정책, 비교, 라이브 데이터, 벤더 선택이 포함되면 먼저 Gemini로 불확실성을 줄인다.
- 출력은 반드시 `research_pack` 또는 `tactical_map`이다.

### 원칙 C. Codex는 bounded write surface만 다룬다

- Codex는 명시적 write 범위와 acceptance command가 있는 계약만 수행한다.
- 작업 중 모호성이 발견되면 설계를 확장하지 않고 `blocked`를 올린다.

### 원칙 D. Queue는 dispatch log가 아니라 workflow database다

- 모든 단계는 `Task Packet`에 이벤트, 계약, 산출물, 상태가 누적된다.
- 재시작, 재배포, 병렬 실행은 packet 상태를 기준으로 동작한다.

### 원칙 E. 복구는 에이전트가 아니라 실패 클래스로 한다

- `rate_limit`, `ambiguous_contract`, `verification_failure`, `stale_session`, `integration_conflict` 등으로 분류한다.
- fallback은 "다음 모델"이 아니라 "이 실패 클래스의 정책"으로 선택한다.

### 원칙 F. 병렬화는 lease 발급 후에만 허용한다

- write surface가 명확히 정해지기 전에는 병렬 실행을 시작하지 않는다.
- 병렬화 단위는 파일 수가 아니라 소유권 경계다.

---

## 4. 목표 아키텍처

```text
User Request
   |
   v
Claude Control Plane
   - intake
   - classify
   - score (U/W/V/T/R)
   - contract
   - route
   - assign leases
   - integrate
   - memory/doc update
   |
   +--> Gemini Intelligence Plane
   |      - research_pack
   |      - tactical_map
   |      - policy/evidence validation
   |
   +--> Codex Execution Plane
   |      - implementation
   |      - test loop
   |      - execution_report
   |
   +--> Claude Review Gate
          - accept/reject
          - merge/join decision
          - residual risk check

Shared Runtime Plane
   - queue/
   - logs/
   - docs/
   - blueprints/
   - artifacts/
```

### 면별 책임

| Plane | 주체 | 책임 | 금지 |
|---|---|---|---|
| Control Plane | Claude | intake, 분해, route, contract, approve, integrate | 대규모 구현, 대규모 리서치 직접 수행 |
| Intelligence Plane | Gemini | evidence 수집, tactical map 작성, 정책 검증 | scope 없는 코드 수정, 최종 merge 판단 |
| Execution Plane | Codex | 구현, 테스트, retry loop, execution report | 요구 재해석, architecture drift |
| Review Gate | Claude | merge 승인, 회귀 판정, memory 승격 | 구현 루프 대체 수행 |

---

## 5. 태스크 분배 전략

v3는 모든 요청을 아래 다섯 축으로 점수화한다.

| 축 | 질문 | 의미 |
|---|---|---|
| `U` Uncertainty | 외부 조사 없이는 설계 결론이 안 나는가 | 높으면 Gemini 선행 |
| `W` Write Surface | 수정 범위와 결합도가 큰가 | 높으면 Codex 우선 |
| `V` Verification Cost | 테스트/빌드/실행 검증이 무거운가 | 높으면 Codex |
| `T` Tool Affinity | MCP, 권한, 브라우저, 계정 조작이 필요한가 | 높으면 Claude |
| `R` Risk | 보안, 데이터 손상, 배포, 정책 리스크가 큰가 | Claude gate 필수 |

### 기본 라우팅 규칙

| 조건 | 라우팅 |
|---|---|
| `T` 높음 | Claude 직접 또는 Claude 주도 |
| `U` 높고 `W` 낮음 | Gemini solo |
| `U` 낮고 `W`,`V` 높음 | Codex solo |
| `U`,`W` 모두 높음 | Gemini -> Claude -> Codex |
| `R` 높음 | 어떤 경우든 Claude review gate 필수 |

### 에이전트별 책임

#### Claude

- `intake -> classify -> contract -> assign -> integrate -> update memory`
- 직접 수행 허용:
  - 1~3파일의 소규모 편집
  - MCP 직접 조작
  - 큐 운영 명령
- 직접 수행 금지:
  - 4개 이상 파일 구현
  - 50라인 이상 신규 코드 생성
  - 100라인 이상 분석/리서치 소화

#### Gemini

- 사용 조건:
  - 외부 문서 조사
  - SDK/벤더 비교
  - 라이브 데이터 확인
  - Codex blocker 해소용 보강 리서치
- 허용 출력:
  - `research_pack.md`
  - `tactical_map.md`
- 금지:
  - 자유형 구현 제안만 던지고 끝내기
  - source URL 없이 주장하기

#### Codex

- 사용 조건:
  - 구현 범위가 명확한 코드/문서 실행
  - 검증 명령이 정의된 작업
- 필수 출력:
  - `execution_report.md`
  - `validation.json`
- 금지:
  - scope 밖 수정
  - 아키텍처 결정을 독단으로 확장

---

## 6. Task Packet 모델

v3에서 `queue/T###_<name>/`는 아래 구조를 가진다.

```text
queue/T123_feature-auth/
  meta.json
  route.json
  contract.yaml
  brief.md
  progress.md
  result.md
  events.jsonl
  locks/
    lease.json
  artifacts/
    index.json
    research_pack.md
    tactical_map.md
    execution_report.md
    validation.json
    recovery.json
```

### 파일 역할

| 파일 | 작성자 | 역할 |
|---|---|---|
| `meta.json` | 시스템 | transport/work/outcome 상태와 기본 메타데이터 |
| `route.json` | Claude | 라우팅 판단, 점수, review gate, fallback policy |
| `contract.yaml` | Claude | 실행 계약의 canonical spec |
| `brief.md` | Claude | 워커에 보낼 사람이 읽기 쉬운 alias |
| `events.jsonl` | 시스템/워커 | 상태 전이와 체크포인트 이벤트 로그 |
| `progress.md` | 워커 | 사람 친화적 진행 메모 |
| `artifacts/index.json` | 시스템 | 산출물 목록과 경로 |
| `result.md` | Claude | 사용자 전달용 최종 요약 |
| `locks/lease.json` | 시스템 | claim owner, expiry, heartbeat |

### 핵심 결정

- `brief.md`는 유지하되 canonical source는 `contract.yaml`이다.
- `result.md`는 워커 raw output이 아니라 Claude가 통합한 최종 요약이다.
- 워커 raw output은 `artifacts/` 아래에 저장한다.

---

## 7. 상태 모델

v3는 상태를 세 층으로 분리한다.

### 7.1 Transport State

- `created`
- `claimed`
- `dispatched`

### 7.2 Work State

- `accepted`
- `running`
- `blocked`
- `retry_wait`
- `awaiting_review`

### 7.3 Outcome State

- `integrated`
- `completed`
- `terminal_failed`
- `superseded`
- `cancelled`

### 권장 `meta.json`

```json
{
  "schema_version": "3",
  "id": "T123",
  "name": "feature-auth",
  "kind": "mixed",
  "owner": "codex",
  "parent_id": null,
  "depends_on": [],
  "transport_state": "dispatched",
  "work_state": "running",
  "outcome_state": null,
  "risk_level": "high",
  "retry_count": 1,
  "reason_code": null,
  "created_at": "2026-03-24T11:00:00+0900",
  "updated_at": "2026-03-24T11:08:00+0900",
  "next_attempt_at": null,
  "review_required": true
}
```

### 상태 불변식

- `completed`는 Claude만 설정한다.
- 워커는 `contract.yaml`의 scope를 수정할 수 없다.
- `blocked`에는 `reason_code`와 `blocking_on`이 필요하다.
- `retry_wait`에는 `next_attempt_at`과 `retry_count`가 필요하다.
- `claimed` 상태 없이 병렬 워커가 같은 task를 집지 못한다.

---

## 8. 협업 프로토콜

### 8.1 Claude -> Worker 계약

`contract.yaml`은 최소한 아래 필드를 가진다.

```yaml
schema_version: "3"
id: T123
kind: mixed
owner: codex
parent_id: null
depends_on: []
goal: "인증 모듈 리팩터링"
scope:
  modify:
    - /abs/path/src/auth/**
  read_only:
    - /abs/path/src/shared/types.ts
  no_touch:
    - /abs/path/scripts/orchestrate.sh
context_budget:
  must_load:
    - /abs/path/src/auth/index.ts
  may_load:
    - /abs/path/tests/auth/*
  do_not_load:
    - /abs/path/reports/**
acceptance:
  commands:
    - npm test -- auth
  conditions:
    - auth 관련 테스트 통과
route:
  scores:
    U: medium
    W: high
    V: high
    T: low
    R: medium
  review_required: true
fallback_policy:
  rate_limit: switch_tier
  ambiguous_contract: escalate_claude
  verification_failure: retry_same_worker
required_artifacts:
  - tactical_map
output_artifacts:
  - execution_report
  - validation
```

### 8.2 Gemini 출력 규격

#### `research_pack.md`

```markdown
## Question
[무엇을 검증했는지]

## Findings
- ...

## Evidence
- [source] URL

## Recommendation
- ...

## Open Questions
- ...
```

#### `tactical_map.md`

```markdown
## Decision
[추천 접근 1줄]

## File-Level Plan
1. path: change
2. path: change

## Constraints
- ...

## Verification
- command
- success condition

## Escalations Needed
- Claude 판단이 필요한 항목만
```

규칙:

- 코딩 관련 mixed task는 `tactical_map.md` 없이 Codex에 직접 넘기지 않는다.
- Gemini는 source URL과 evidence 없이 결론을 제출할 수 없다.

### 8.3 Codex 출력 규격

#### `execution_report.md`

```markdown
## Files Changed
- path

## Behavior Change
- before -> after

## Verification
- command
- PASS | FAIL

## Residual Risks
- ...

## Blockers
- none | ...
```

#### `validation.json`

```json
{
  "commands": [
    {
      "command": "npm test -- auth",
      "status": "pass"
    }
  ],
  "summary": "auth tests passed"
}
```

### 8.4 이벤트 로그

모든 상태 변화는 `events.jsonl`에 남긴다.

```json
{"ts":"2026-03-24T11:00:00+0900","actor":"claude","event":"route_created","detail":"U=medium,W=high,V=high,T=low,R=medium"}
{"ts":"2026-03-24T11:01:00+0900","actor":"system","event":"claimed","detail":"owner=codex"}
{"ts":"2026-03-24T11:03:00+0900","actor":"codex","event":"accepted","detail":""}
{"ts":"2026-03-24T11:10:00+0900","actor":"codex","event":"awaiting_review","detail":"execution_report ready"}
```

이벤트 로그는 stale session 복구와 사후 분석의 기준이 된다.

---

## 9. Blueprint와 Chain 통합

### 현재 문제

- `scripts/run_blueprint.py`는 step 결과를 stdout으로 다음 step에 넘긴다.
- `--chain`은 큐 엔트리를 만들지만 typed artifact와 richer state를 우회한다.

### v3 원칙

모든 멀티스텝 흐름은 parent-child DAG로 들어간다.

```text
Parent Task T200
  ├─ T201 research
  ├─ T202 tactical-map
  ├─ T203 implement-shard-a
  └─ T204 review
```

### 규칙

- blueprint step마다 child task를 생성한다.
- `depends_on`은 child task reference로 관리한다.
- 다음 step은 직전 stdout이 아니라 `artifacts/index.json`에 등록된 파일을 입력으로 받는다.
- `--chain`은 장기적으로 deprecated 하거나 DAG packet protocol 위에 래핑한다.

### 권장 blueprint spec

```yaml
name: feature-dev
vars:
  task: null
  project_path: null
steps:
  - id: research
    kind: research
    owner: gemini
    outputs: [research_pack]
  - id: tactical_map
    kind: research
    owner: gemini
    depends_on: [research]
    inputs:
      - artifact: research_pack
    outputs: [tactical_map]
  - id: implement
    kind: code
    owner: codex
    depends_on: [tactical_map]
    inputs:
      - artifact: tactical_map
    outputs: [execution_report, validation]
```

---

## 10. 병렬 협업 프로토콜

### 10.1 Discovery Gate

lease 발급 전 반드시 아래를 완료한다.

1. write surface 식별
2. 공용 인터페이스 owner 식별
3. acceptance command 확정
4. shard boundary 고정

이 네 가지가 없으면 병렬화 금지다.

### 10.2 Lease 모델

`locks/lease.json`

```json
{
  "lease_owner": "codex",
  "lease_scope": {
    "modify": ["/abs/path/src/auth/**"],
    "read_only": ["/abs/path/src/shared/types.ts"]
  },
  "claimed_at": "2026-03-24T11:03:00+0900",
  "expires_at": "2026-03-24T11:33:00+0900",
  "heartbeat_at": "2026-03-24T11:08:00+0900"
}
```

규칙:

- lease 없는 write는 invalid다.
- lease가 겹치면 Claude가 재분할한다.
- 공용 파일은 별도의 integration owner만 수정한다.

### 10.3 권장 병렬 패턴

#### Pattern A. Scout -> Builder

- Gemini 조사
- Claude 계약 확정
- Codex 구현

#### Pattern B. Split Builders

- Claude가 shard lease를 발급
- Codex shard 1, shard 2 병렬 실행
- Claude 또는 지정된 integration owner가 merge

#### Pattern C. Research Sidecar

- Codex가 구현 중
- Gemini가 sidecar로 회귀 리스크나 정책 근거를 확인
- Claude가 최종 판정

---

## 11. 실패 복구 플로우

### 11.1 실패 클래스

| 클래스 | 예시 | 1차 처리 | 2차 처리 |
|---|---|---|---|
| `rate_limit` | quota, 429 | 같은 family 내 tier 전환 | degraded mode 또는 requeue |
| `transient_cli` | CLI crash, network hiccup | 같은 worker 재시도 | 다른 transport node |
| `ambiguous_contract` | 요구 상충, 스코프 불명확 | Claude 에스컬레이션 | Gemini clarification task |
| `scope_violation` | 범위 밖 파일 필요 | blocker 생성 | scope 재설계 |
| `verification_failure` | 테스트 실패 | 같은 worker 재시도 | Claude review 후 재분해 |
| `integration_conflict` | 병렬 결과 충돌 | integration owner 지정 | 직렬 merge 재실행 |
| `stale_session` | 세션 종료, 중간 결과 미회수 | `events.jsonl` 기반 resume | 마지막 artifact 기준 재개 |
| `missing_evidence` | 리서치 근거 부족 | Gemini 보강 요청 | 질문 축소 |

### 11.2 복구 알고리즘

1. 실패 감지
2. `events.jsonl`와 raw log 저장
3. failure class 부여
4. 해당 클래스 정책 적용
5. `artifacts/recovery.json` 기록
6. 자동 복구 불가 시 `blocked` 또는 `terminal_failed`

### 11.3 `recovery.json` 예시

```json
{
  "failure_class": "verification_failure",
  "detected_at": "2026-03-24T11:15:00+0900",
  "retry_count": 2,
  "action": "escalate_claude_review",
  "next_state": "awaiting_review"
}
```

---

## 12. Degraded Mode

v3는 각 에이전트 family별로 저하 운영 모드를 정의한다.

### `claude_constrained`

- 조건:
  - Claude usage limit 임박
  - orchestrator context budget 부족
- 정책:
  - route를 config 기반 deterministic rule로 제한
  - optional review gate 생략
  - 새 아키텍처 합성 금지

### `gemini_unavailable`

- 조건:
  - quota 고갈
  - 네트워크/CLI 장애
- 정책:
  - 외부 불확실성이 낮은 작업만 Codex solo 허용
  - 외부 리서치가 필수인 mixed task는 queue

### `codex_unavailable`

- 조건:
  - Codex CLI 장애
  - 코딩 quota 문제
- 정책:
  - code task는 queue
  - research/documentation task만 진행
  - Gemini의 fallback code generation은 임시 예외로만 허용

### 운영 원칙

- degraded mode는 `agent_config.yaml`에 명시한다.
- fallback은 "다음 모델"보다 "이 degraded mode에서 허용되는 작업"을 우선 본다.

---

## 13. `agent_config.yaml` 확장 제안

현재 config는 model tier와 fallback에 강하다. v3는 아래 섹션을 추가한다.

```yaml
routing:
  mixed_requires_research_first: true
  high_risk_requires_claude_review: true
  max_claude_direct_write_surface: 3
  require_tactical_map_for_mixed_code: true

failure_class_policies:
  rate_limit:
    action: switch_tier_then_requeue
  ambiguous_contract:
    action: escalate_claude
  verification_failure:
    action: retry_same_worker_then_review

degraded_modes:
  claude_constrained:
    allow_optional_review: false
  gemini_unavailable:
    allow_external_uncertainty_tasks: false
  codex_unavailable:
    allow_code_tasks: false
```

이렇게 해야 Claude의 암묵지를 config로 옮길 수 있다.

---

## 14. 운영 규칙

### 필수 규칙

- mixed task는 `research_pack` 또는 `tactical_map` 없이 Codex로 직접 보내지 않는다.
- `route.json` 없는 task는 dispatch하지 않는다.
- `lease.json` 없는 병렬 write는 금지한다.
- `events.jsonl` 없는 상태 전이는 invalid다.
- `completed`는 Claude review gate를 통과한 뒤에만 설정한다.

### 금지 규칙

- 같은 파일에 대한 중복 lease
- source URL 없는 Gemini 결론
- acceptance command 없는 Codex 코드 작업
- `--resume`이 claim 없이 task를 재실행하는 것
- blueprint step stdout을 다음 step prompt에 그대로 붙이는 것

---

## 15. 운영 지표

| 지표 | 정의 | 목표 |
|---|---|---|
| Contract clarity rate | 추가 질문 없이 `accepted`된 태스크 비율 | 높을수록 좋음 |
| Artifact reuse rate | 기존 artifact를 후속 step이 재사용한 비율 | 높을수록 좋음 |
| First-pass verification rate | 첫 실행에서 acceptance를 통과한 비율 | 높을수록 좋음 |
| Recovery success rate | 자동 복구로 완료된 실패 비율 | 높을수록 좋음 |
| Duplicate dispatch rate | 동일 task 중복 실행 비율 | 0에 가깝게 |
| Integration conflict rate | 병렬 shard 충돌 비율 | 낮을수록 좋음 |
| Mean time to recover | 실패 감지부터 재가동까지 평균 시간 | 낮을수록 좋음 |

로그에 최소한 아래 필드를 남긴다.

- `failure_class`
- `parent_id`
- `depends_on`
- `lease_owner`
- `retry_count`
- `degraded_mode`

---

## 16. 구현 우선순위

### Phase 1. Packet 확장

- `schema_version` 추가
- `route.json`, `events.jsonl` 도입
- `meta.json`을 layered state로 확장
- `brief.md`, `result.md`는 backward compatible 유지

### Phase 2. Artifact 핸드오프

- Gemini 결과를 `artifacts/research_pack.md` 또는 `artifacts/tactical_map.md`로 저장
- Codex가 artifact path를 읽도록 변경
- `scripts/run_blueprint.py`에서 raw stdout interpolation 제거

### Phase 3. Claim/Lease

- `locks/lease.json` 도입
- `--resume`은 claim 가능한 task만 집도록 변경
- stale task 복구를 `events.jsonl` 기반으로 전환

### Phase 4. Parent-Child DAG

- blueprint step을 child task로 생성
- `parent_id`, `depends_on`, `join_policy` 도입
- `--chain`을 DAG packet protocol로 래핑하거나 deprecated

### Phase 5. Policy-Driven Recovery

- `agent_config.yaml`에 `routing`, `failure_class_policies`, `degraded_modes` 추가
- fallback을 model chain에서 failure policy 중심으로 전환

### Phase 6. Review Gate 강화

- high-risk task는 Claude review 없이는 `completed` 금지
- 필요 시 Gemini sidecar validation 연결

---

## 17. 최종 설계 결론

v3의 핵심은 새로운 에이전트를 더 붙이는 것이 아니다. 이미 있는 Claude, Codex, Gemini를 더 엄격한 runtime contract 안으로 집어넣는 것이다.

최종 의사결정은 아래와 같다.

1. Claude는 계속 single brain이지만, 판단은 `route.json`과 `contract.yaml`로 외화한다.
2. Gemini와 Codex 사이의 handoff는 raw text가 아니라 artifact reference 기반으로 바꾼다.
3. 큐 상태는 단일 `status`가 아니라 transport/work/outcome으로 분리한다.
4. 병렬 협업은 claim과 lease 도입 이후에만 허용한다.
5. 실패 복구는 fallback chain이 아니라 failure class와 degraded mode를 중심으로 설계한다.

이 다섯 가지가 적용되면 이 저장소의 멀티 에이전트 시스템은 "잘 굴러가는 스크립트 모음"에서 "복구 가능하고 확장 가능한 협업 런타임"으로 올라간다.
