$ARGUMENTS 에 해당하는 항목을 완료 처리한다. 순서대로 실행해라.

1. **SCHEDULE.md 체크박스 업데이트**
   - `mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")` 로 읽어라.
   - $ARGUMENTS 와 가장 일치하는 항목을 찾아라 (부분 일치 허용).
   - 해당 항목의 `- [ ]` 또는 `- [/]` 를 `- [x]` 로 변경해라.
   - `mcp__obsidian-vault__patch_note("30-projects/schedule/SCHEDULE.md", oldString, newString)` 으로 저장.
   - SCHEDULE.md에 없으면 BACKLOG.md (`mcp__obsidian-vault__read_note("30-projects/schedule/BACKLOG.md")`)도 확인해라. 있으면 동일하게 patch.

2. **Daily 로그 기록**
   - 오늘 날짜로 `mcp__obsidian-vault__read_note("40-log/YYYY-MM-DD.md")` 를 시도해라.
   - 파일이 없으면 아래 frontmatter로 새로 생성해라:
     ```
     mcp__obsidian-vault__write_note("40-log/YYYY-MM-DD.md", content, frontmatter={type: "log", date: "YYYY-MM-DD", status: "active"})
     ```
     기본 내용:
     ```
     # YYYY-MM-DD

     ## 완료
     ```
   - `mcp__obsidian-vault__patch_note` 또는 `write_note(mode: "append")` 로 `## 완료` 섹션에 추가해라:
     `- [x] [우선순위] 항목명 #카테고리`

3. **완료 메시지 출력**
   - "완료: [항목명] → ✓ vault SCHEDULE.md + 40-log" 형식으로 출력.
