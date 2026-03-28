이번 주 회고를 진행한다.

$ARGUMENTS: 없으면 이번 주(월~오늘) 기준. 숫자가 있으면 해당 주 전(`2` → 2주 전).

---

## Phase 1: 데이터 수집 (병렬 실행)

다음 3개를 동시에 읽어라:

1. **SCHEDULE.md**:
   ```
   mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")
   ```

2. **이번 주 일별 로그** (월~오늘):
   ```
   mcp__obsidian-vault__read_multiple_notes(["40-log/YYYY-MM-DD.md", ...])
   ```

3. **git log**:
   ```bash
   git -C ~/projects/agent-orchestration log --oneline --since="7 days ago"
   ```

---

## Phase 2: 분석 + 출력

아래 형식으로 출력해라:

```
📅 주간 회고 — [날짜 범위]

**이번 주 완료**
- 40-log + git log 기반 정리 (날짜 역순)

**진행 중**
- SCHEDULE.md [높]/[중] 미완료 항목

**다음 주 포커스 Top 3**
- 밀린 [높] 항목, 마감 임박 항목 우선

**한 줄 총평**
- 솔직하게
```

---

## Phase 3: 후속 액션 제안

출력 후 AskUserQuestion을 호출해라:
- 질문: "회고 결과를 바탕으로 다음 액션을 선택하세요." (header: "후속 액션")
- A) SCHEDULE.md 업데이트 — 완료 항목 체크, 다음 주 항목 추가
- B) vault 저장 — 회고 내용을 vault에 기록
- C) 그냥 참고만 — 추가 작업 없음
