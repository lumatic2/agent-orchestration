$ARGUMENTS 에 해당하는 항목을 연기한다. (부분 일치 허용)

순서대로 실행해라:

1. **항목 찾기**
   - `mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")` 로 읽어라.
   - $ARGUMENTS 와 가장 일치하는 항목을 찾아라.
   - SCHEDULE.md에 없으면 `mcp__obsidian-vault__read_note("30-projects/schedule/BACKLOG.md")` 도 확인.
   - 찾은 항목을 사용자에게 보여주며 맞는지 확인해라: "이 항목을 연기할까요? [항목 전체 텍스트]"

2. **연기 방법 선택**
   사용자에게 선택지 제시:
   - **날짜 변경**: 새 마감일 입력 (예: 03-28)
   - **BACKLOG 이동**: 마감 없이 Anytime으로 이동

3. **vault 업데이트**
   - **날짜 변경 시**:
     - `mcp__obsidian-vault__patch_note` 로 날짜 태그만 교체 (예: `03-22(일)` → `03-28(토)`)
   - **BACKLOG 이동 시**:
     - SCHEDULE.md에서 해당 항목 줄 삭제 (`patch_note` oldString=항목줄, newString="")
     - BACKLOG.md `## 언제든 (Anytime)` 해당 카테고리 섹션에 날짜 태그 제거 후 append
       (`mcp__obsidian-vault__patch_note("30-projects/schedule/BACKLOG.md", ...)`)

4. **완료 메시지 출력**
   - "연기: [항목명] → [새 날짜 or BACKLOG 이동]"
