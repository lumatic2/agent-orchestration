$ARGUMENTS 형식으로 항목을 추가한다.
형식 예시: "[높] 예비창업패키지 제출 #회사 03-24" 또는 "[중] 책 읽기 #학습"

순서대로 실행해라:

1. **$ARGUMENTS 파싱**
   - 우선순위: `[높]`, `[중]`, `[낮]`, `[-]` (없으면 `[-]`)
   - 항목명: 우선순위 태그와 카테고리 태그, 날짜 제외한 나머지
   - 카테고리: `#회사`, `#개발`, `#학습`, `#크리에이티브`, `#라이프`, `#노션` (없으면 생략)
   - 마감일: `MM-DD` 형식 날짜 (없으면 없음)

2. **대상 파일 결정**
   - 마감일 있으면 → SCHEDULE.md `## 마감 있음 (Deadline)` 섹션에 추가
   - 마감일 없으면 → 사용자에게 확인:
     "TODAY(오늘 할 것) 또는 BACKLOG(나중에)?"
     - TODAY 선택 → SCHEDULE.md `## 오늘 (Today)` 섹션에 해당 카테고리 아래 추가
     - BACKLOG 선택 → BACKLOG.md `## 언제든 (Anytime)` 섹션에 해당 카테고리 아래 추가

3. **vault에 저장**
   - SCHEDULE.md에 추가 시: `mcp__obsidian-vault__patch_note("30-projects/schedule/SCHEDULE.md", ...)`
   - BACKLOG.md에 추가 시: `mcp__obsidian-vault__patch_note("30-projects/schedule/BACKLOG.md", ...)`
   - patch_note의 oldString은 해당 섹션의 마지막 항목 또는 섹션 헤더로 찾아라.
     섹션 마지막에 새 줄로 append하는 방식 사용.

4. **완료 메시지 출력**
   - "추가: [항목명] → [SCHEDULE.md 마감 / SCHEDULE.md Today / BACKLOG.md]"
