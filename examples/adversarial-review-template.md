# Adversarial Review Chain — Template

> 새 Claude Code 세션에 복사해서 쓸 수 있는 적대적 리뷰 체인 프롬프트. 이 파일을 그대로 첨부하면 Claude가 아래 규칙대로 체인을 돈다.
>
> 실제 1회분 세션 예시: [`adversarial-review.md`](./adversarial-review.md)

## 사용법

새 Claude Code 세션에서 다음 프롬프트를 사용:

```
다음 작업을 적대적 리뷰 체인으로 진행해:

[작업 설명 — 한 줄~한 단락]
타겟 파일: [경로]

체인 규칙은 ~/Projects/agent-orchestration/examples/adversarial-review-template.md 를 따라.
```

Claude는 아래 단계를 자동으로 수행해야 한다.

## 전제 조건

- `mcp__codex-mcp__codex_run` / `mcp__gemini-mcp__gemini_run` 도구 노출 확인
- 타겟 경로가 `C:/Users/1/Projects/agent-orchestration/` 내부 (Codex workspace-write sandbox)
- Infrastructure File Protection 목록(`scripts/sync.sh`, `adapters/claude_global.md`, `SHARED_PRINCIPLES.md` 등)을 건드리지 않는 작업

## 단계

### 1. Codex 1차 구현

```
mcp__codex-mcp__codex_run({
  prompt: "[작업 설명] + 톤 단서: '빠르게 짜봐, 과방어 금지'",
  cwd: "C:/Users/1/Projects/agent-orchestration",
  write: true,
  model: "spark",          // 단순하면 spark, 그 외 생략
  effort: "medium"
})
```

**중요**: 1차 프롬프트에 input validation을 미리 요청하지 마라. 그러면 적대적 리뷰가 잡을 거리가 사라진다. 방어 코드는 2차에서 추가한다.

### 2. Diff 수집

```
git diff --stat <target-dir>
```

크기 임계값:
- **<200줄**: `git diff` 전체를 그대로 리뷰어에 전달
- **200~500줄**: 파일별로 분할, 각 파일을 별도 `gemini_run` 호출로
- **500줄+**: Claude가 먼저 파일별 요약 → 의심 hunk만 골라서 전달

### 3. Gemini 적대적 리뷰

```
mcp__gemini-mcp__gemini_run({
  prompt: `<adversarial review prompt — 아래 템플릿>`,
  model: "flash",          // 코드가 짧으면 flash, 복잡한 도메인 로직이면 pro
  timeoutMs: 180000        // 기본 600s는 너무 길다. 3분이면 충분
})
```

리뷰 프롬프트 템플릿:
```
You are an adversarial code reviewer. Your job is to BREAK the following code.
Focus on inputs that cause it to:
- silently return wrong answers (the worst kind of bug)
- accept clearly invalid input without raising
- mishandle edge cases (overflow, negatives, whitespace, mixed/duplicate units, ordering, fractions, locale)
- be exploitable (regex catastrophic backtracking, injection, race condition)

For each issue, provide:
1. A concrete attack input (exactly what to pass)
2. What the code returns/does for that input
3. What it SHOULD do
4. Severity: HIGH (silent wrong answer) / MEDIUM (accepts garbage) / LOW (cosmetic)

Skip vague critiques like "lacks type hints" or "should add tests".
Only concrete, reproducible attacks.

```<diff or code>```
```

#### 3a. Fallback (Gemini hang/429)

`gemini_run`이 timeout 또는 5xx/429로 실패하면:

1. `gemini_cancel(jobId)` — 좀비 job 정리
2. **1회 재시도** (timeoutMs를 절반으로 줄이고)
3. 재시도도 실패 → **Claude가 직접 적대적 리뷰 수행**. 체인 전체를 죽이지 마라. fallback 발동을 사용자에게 알리고, 실제 발견 표를 출력.

⚠️ 2026-04-08 시점 `gemini-3-flash-preview`는 hang 빈도가 높다. fallback은 "선택지"가 아니라 "기본 보험"으로 취급하라.

### 4. Claude 심판

수용 기준:
- ✅ **재현 가능한 입력 + 구체적 잘못된 출력**이 있는 지적 → 수용
- ❌ "잘 짜진 코드인 것 같지만 더 견고하게 …" 같은 개념적 비판 → 기각
- ❌ "타입 힌트/주석/테스트 부족" 같은 코드 위생 지적 → 기각 (이 체인의 목적이 아님)
- HIGH/MEDIUM은 모두 수용, LOW는 비용 대비 가치로 판단

수용 결과를 표로 정리해서 사용자에게 보여줄 것.

수용된 지적이 0개면 → **체인 종료**, "리뷰가 유효한 공격을 찾지 못함, 1차 코드 그대로 채택" 보고. 억지로 수정하지 말 것.

### 5. Codex 2차 — 수정 반영

```
mcp__codex-mcp__codex_run({
  prompt: "Adversarial review found N bugs. Fix each: [수용된 지적 목록 with expected ValueError messages] ... Verify with: [구체적 CLI 명령 + 기대 출력]",
  cwd: "...",
  write: true,
  resume: true,            // 같은 thread 이어가기
  model: "spark", effort: "medium"
})
```

#### 5a. resume 막힘 fallback

좀비 job 때문에 `resume=true`가 "still running" 에러로 막히면:
1. `codex_status(jobId)`로 stuck job 식별
2. `codex_cancel` 시도 (Git Bash에서는 path mangling 버그 있음 → 실패 시 `cmd //c "taskkill /PID <pid> /T /F"`)
3. 그래도 안 풀리면 **`fresh=true`로 새 thread**. 이 체인 한정으로는 thread 연속성보다 진행이 우선.

### 6. 검증

수용된 지적별로 1개씩 입력 케이스를 만들어 실행 + 정상 입력 1개 추가:
```bash
python <target> <attack-input-1>   # ValueError 기대
python <target> <attack-input-2>   # ValueError 기대
...
python <target> <valid-input>      # 정확한 값 기대
```

전부 통과해야 done.

### 7. 재시도 상한

**최대 2회 재시도** (= Codex 호출 총 3회). 그 이상은 리뷰 자체가 잘못된 가설이거나 코드 구조가 부적절한 신호. 사용자에게 보고 후 중단.

```
시도 1: 1차 구현
시도 2: 적대적 리뷰 1차 반영
시도 3: 잔여 지적 또는 시도 2 실패 회복
시도 4+: 금지. 사용자 개입 요청.
```

## 산출물

체인 종료 후:
1. 사용자에게 **요약 표** 출력 (지적/수용/반영/검증 결과)
2. 변경 파일 git status로 표시
3. **자동 commit 금지** — 사용자가 명시 요청해야 commit

## 절대 금지

- 1차 구현 프롬프트에 방어 코드를 미리 요청 (리뷰 무력화)
- 적대적 리뷰 결과를 무비판 수용 (false positive 폭주의 원흉)
- 재시도 4회 이상
- Infrastructure File Protection 목록 수정
- 사용자 승인 없는 commit/push

## 적합/부적합 작업

**적합**:
- 입력 파싱·검증 (오늘 세션의 parse_duration 같은 케이스)
- 권한·인증 체크
- 외부 입력을 받는 API 핸들러
- 보안 sensitive 코드(SQL builder, 경로 정규화 등)

**부적합**:
- 단순 리팩토링 (의미 보존만 검증하면 됨, 적대적 입력 개념이 없음)
- UI 코드 (시각 검증이 본질)
- 마이그레이션 스크립트 (1회성, 적대적 입력보다 dry-run이 적합)
- 1차 코드가 50줄 미만이면서 분기 없는 케이스 (리뷰가 잡을 게 없음)
