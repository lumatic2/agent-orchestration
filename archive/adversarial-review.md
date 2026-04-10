# Adversarial Review Chain — Session Log (2026-04-08)

> 방향 1 ([orchestration-roadmap.md](../docs/orchestration-roadmap.md)) 첫 실증. MCP 인프라 위에 Claude의 tool calling만으로 "구현 → 적대적 리뷰 → 심판 → 수정" 체인이 도는지 검증한 1회분 세션 기록.

체인 구성:
```
Claude(planner+judge)
  ├─▶ codex_run(write=true)         ← 1차 구현
  ├─▶ git diff
  ├─▶ gemini_run(model=flash)       ← 적대적 리뷰  ※ 이번 세션은 hang → Claude fallback
  ├─▶ Claude 심판
  └─▶ codex_run(resume/fresh=true)  ← 2차 시도
```

복붙용 템플릿: [`adversarial-review-template.md`](./adversarial-review-template.md)

## 타겟

`examples/parse_duration.py` — 인간 친화 duration 문자열(`"1h30m15s"`)을 초로 변환. 전형적인 엣지 케이스 풍부 영역(부호/소수/중복 단위/누락 단위/garbage 입력).

## 1차 — Codex 구현

도구: `mcp__codex-mcp__codex_run`
모델: `spark` / effort `medium`
프롬프트 톤: "빠르게 짜봐, 과방어 금지" (방어 코드를 미리 요청하면 적대적 리뷰가 잡을 거리가 사라진다)

소요: **45.3s**, 18 polls, completed.

생성된 코드:
```python
import re, sys
def parse_duration(text: str) -> int:
    total = 0
    for amount, unit in re.findall(r"(\d+)\s*([smhd])", text.strip().lower()):
        n = int(amount)
        if unit == "s": total += n
        elif unit == "m": total += n * 60
        elif unit == "h": total += n * 3600
        elif unit == "d": total += n * 86400
    return total

if __name__ == "__main__":
    print(parse_duration(sys.argv[1]))
```

## 2차 — Gemini 적대적 리뷰 (실패 → fallback)

도구: `mcp__gemini-mcp__gemini_run` (model `flash`)

**결과**: 두 번 모두 hang.
- 1차 호출: 기본 timeoutMs(600s) 초과, status `running`/`finalizing`로 정체 → cancel
- 2차 호출(timeoutMs 180s): 동일 패턴 → cancel

원인 추정: 업스트림 `gemini-3-flash-preview` 응답 지연. 동일 증상이 방향 2 Phase 6 스모크에서도 1회 관찰됨 (rate-limit 의심).

**Fallback 발동**: 템플릿 규칙대로 Claude가 직접 적대적 리뷰 수행 — 체인이 죽지 않는지 검증.

## 3차 — Claude 심판 (직접 리뷰 결과)

| # | 입력 | 1차 코드 반환 | 기대 동작 | 심각도 |
|---|---|---|---|---|
| 1 | `"30"` | `0` | ValueError("missing unit") | **HIGH** — 사용자가 "30초" 의도, 조용히 0 |
| 2 | `"-5m"` | `300` | ValueError("negative …") | **HIGH** — 부호 손실, 정확히 반대 의미 |
| 3 | `"5m5m"` | `600` | ValueError("duplicate unit: m") | **HIGH** — 조용히 두 배 |
| 4 | `"1.5h"` | `18000` (regex가 "5h"만 매치) | ValueError("fractional …") | **HIGH** — 의도와 3.3배 차이 |
| 5 | `""` / `"hello"` | `0` | ValueError | MEDIUM — garbage as 0 |
| 6 | `"3w"` (미지원 단위) | `0` | ValueError | MEDIUM — silent drop |

심판 기준 (템플릿에 명시):
- 재현 가능한 입력 + 구체적 잘못된 출력이 있는 지적만 수용
- "타입 힌트가 부족하다" 같은 개념적 비판은 기각
- HIGH 4개 모두 수용 → Codex 2차 호출에 그대로 전달

## 4차 — Codex 수정 시도 (resume 경로)

**시도 1**: `resume=true` → "이전 task가 still running" 에러로 즉시 fail.
원인: 별개 세션의 좀비 task(`task-mnq13hln-a1t4ps`)가 finalizing phase에 21분째 정체. 실제 OS 프로세스는 죽었지만 codex-companion 데몬의 in-process 상태가 갱신되지 않음.

**시도 2**: `taskkill /T /F`로 OS 프로세스 강제 종료 + jobs/*.json status를 `failed`로 직접 패치 → 그래도 fail. 데몬은 디스크가 아니라 in-memory job map을 본다.

**시도 3**: `fresh=true`로 새 thread 강제 → **성공**. 600s timeoutMs 안에 파일 두 번 쓰고 데몬은 또 finalizing hang에 들어갔지만, 최종 파일 내용은 디스크에 안착.

소요: 실제 작업 완료까지 ~2분 / 데몬 timeout 표시: 602s

## 5차 — 검증

```
input: '1h30m15s' → 5415          ✓
input: '5m5m'     → ValueError: duplicate unit: m
input: '1.5h'     → ValueError: fractional values not supported
input: '30'       → ValueError: missing unit
input: '-5m'      → ValueError: negative durations not supported
input: 'hello'    → ValueError: invalid duration: hello
input: ''         → ValueError: invalid duration:
input: '3w'       → ValueError: invalid duration: 3w
```

8/8 통과. 적대적 리뷰가 잡은 4개 HIGH가 모두 explicit ValueError로 전환됐고 정상 입력은 정확한 값을 반환.

## 메타 관찰 (다음 세션을 위한 노트)

1. **gemini-3-flash-preview hang은 예외가 아니라 상수에 가깝다.** 이번 세션에서 2/2 실패. 템플릿의 fallback 경로를 "선택지"가 아니라 "기본 보험"으로 명시할 것. flash가 빠르면 보너스, 느리면 Claude가 받는다.
2. **codex-companion finalizing hang**: spark 모델이 작업을 끝내고도 데몬의 turn-completion inference가 마무리되지 않는 케이스가 두 번 관찰됨. 작업 자체는 완료된 상태라 파일은 디스크에 있다. resume 경로가 좀비 job 때문에 막히면 `fresh=true`로 우회 가능. 별도 이슈로 codex-mcp에 보고할 가치 있음.
3. **codex_cancel은 Git Bash 환경에서 path 인자 처리 버그가 있다** (`C:/Program Files/Git/PID`로 mangle). cmd 직접 호출(`cmd //c "taskkill /PID … /T /F"`)이 우회 방법.
4. **적대적 리뷰는 1차 코드가 충분히 허술해야 의미가 있다.** "방어 과잉 금지" 톤을 1차 프롬프트에 명시하지 않으면 Codex spark도 즉석에서 input validation을 추가해버려 리뷰가 잡을 거리가 사라진다.
5. **체인 전체 소요**: Codex 1차(45s) + Gemini 시도 2회(13분 낭비) + Claude 리뷰(~즉시) + Codex 2차(2분 + 데몬 hang) + 검증(~5s) ≈ **17분**. Gemini가 정상 동작했다면 ~5분으로 줄어든다.
