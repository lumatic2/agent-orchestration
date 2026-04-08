# Final Report Template — Deep Research B

> 루프 종료 후 Claude 가 직접 작성. Gemini/Codex 재호출 없음.
> 저장 위치: `data/deep-research/{slug}/report.md` (스테이징) → 사용자 승인 후 vault.

## 구조

최종 보고서는 `success_criteria` 순서를 그대로 목차로 사용한다. 체크리스트가 이미 "답의 구조" 역할을 했기 때문.

```markdown
---
title: <원질문 재진술>
slug: <kebab-case>
date: YYYY-MM-DD
source: deep-research-b
type: research
domain: <scope.intent.where 에서>
status: draft
rounds: N
final_coverage: X/Y (Z%)
wall_clock_minutes: M
termination_reason: <coverage-full | stagnation | max-rounds | skeptic-failed | wall-clock | stop-file>
---

# <원질문>

## TL;DR

3~5 줄 요약. 독자가 여기만 읽어도 핵심 답을 받아야 한다. 불확실한 부분은
"unclear" 또는 "no evidence found" 라고 명시 — 억지로 답하지 마라.

## 의사결정 요약 (해당 시)

scope.intent.why 가 "결정" 이었다면, 권고 + 그 근거가 되는 1~3 개 claim 을
인용. 아니면 이 섹션 생략.

## 핵심 발견 — Coverage 체크리스트 기준

각 success_criterion 을 섹션으로. 순서는 scope 작성 순.

### Criterion 1 — <원문>

**Status**: ✓ filled / partial / ✗ unfilled

**Findings**:
- [c-r2-003] <claim 본문> — source: <URL> (PRIMARY/SECONDARY/TERTIARY)
- [c-r3-011] <claim 본문> — source: <URL>

**Confidence**: high / medium / low
이유: 출처 유형 + Skeptic 검증 통과 여부 + 출처 수.

### Criterion 2 — ...
...

### Criterion N — <unfilled criterion 이름>

**Status**: ✗ unfilled

라운드 N 동안 이 항목을 채우는 증거를 찾지 못함. 시도한 쿼리:
- Round X: <쿼리 요약>
- Round Y: <쿼리 요약>

가능한 이유: <데이터 자체 부재 / 검색 범위 한계 / scope 미스매치>.

## 알려지지 않은 것 (known unknowns)

Coverage 가 채우지 못한 항목을 한데 모아 목록화. 후속 리서치의 출발점.

- <unfilled criterion 1> — 왜 못 찾았는지
- <Skeptic 이 flag 한 downgraded claim 중 재검토 필요한 것>
- <scope out_of_scope 였지만 라운드 중 중요하다고 판명된 것>

## 반대 증거 / 이견

Skeptic 이 수용한 counter-evidence 와 DOWNGRADED 된 claim. 독자가
"이 보고서가 놓쳤을 수 있는 것" 을 빠르게 볼 수 있게.

- [c-rN-XXX] original claim → counter: <내용> (source: <URL>)

## 방법론

- Rounds: N
- Gemini pro branches per round: 3
- Codex Skeptic calls: N (1 per round)
- Wall clock: M minutes
- Termination: <reason>
- Scope checklist revised: yes/no (Round 1 재작성 허용)

## 출처 목록

PRIMARY 와 SECONDARY 만 나열. TERTIARY 는 인라인 인용만, 여기엔 제외.

1. <title> — <url> — PRIMARY — <1줄 요약>
2. ...

## 라운드 로그 인덱스

- Round 1: `round-1.md` — coverage X/Y, 쿼리 주제 <...>
- Round 2: `round-2.md` — coverage X/Y, 쿼리 주제 <...>
- ...
```

## 작성 규칙

1. **claim id 유지**: 라운드 로그의 claim id (c-rN-XXX) 를 최종 보고서에서도 그대로 써라. 검증 경로가 끊기지 않아야 한다.
2. **unfilled 를 숨기지 마라**: 빈 체크리스트 항목은 반드시 섹션으로 나타나야 한다. 빈 줄로 생략하면 "답이 나온 것처럼" 오독된다.
3. **출처 bucket 을 claim 옆에 괄호로**: 독자가 신뢰도를 인라인으로 판단.
4. **Claude 가 새 claim 을 추가하지 마라**: Judge 단계에서 살아남은 claim 만 쓴다. 최종 보고서는 집계일 뿐, 추가 리서치 단계가 아니다.
5. **TL;DR 에 불확실성 표시**: "X 기법이 우세" ❌ → "X 기법이 우세로 보이지만 2026-03 기준 primary 출처 2건, 벤치마크 재현 미확인" ✅

## vault 저장 게이트

스테이징 파일 위치: `data/deep-research/{slug}/report.md`

사용자에게 다음을 보여주고 승인 요청:

```
Deep Research 보고서 준비 완료:
- slug: <slug>
- rounds: N
- coverage: X/Y (Z%)
- wall clock: M 분
- termination: <reason>
- 스테이징: data/deep-research/{slug}/report.md

vault 저장 원하시면 승인해주세요. 저장 시:
→ 10-knowledge/research/{slug}.md
→ frontmatter: type=research, domain=<...>, source=deep-research-b, date=<...>, status=draft
```

**절대 금지**: 사용자 승인 없이 `mcp__obsidian-vault__write_note` 호출. 체인 밖에서 자동 저장도 금지.
