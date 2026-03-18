$ARGUMENTS 에 해당하는 항목을 완료 처리한다. 순서대로 실행해라.

1. **SCHEDULE.md 체크박스 업데이트**
   - ~/projects/agent-orchestration/SCHEDULE.md 를 읽어라.
   - $ARGUMENTS 와 가장 일치하는 항목을 찾아라 (부분 일치 허용).
   - 해당 항목의 `- [ ]` 를 `- [x]` 로 변경해라.
   - SCHEDULE.md에 없으면 BACKLOG.md (`~/projects/agent-orchestration/BACKLOG.md`)도 확인해라.

2. **Daily 로그 기록**
   - 오늘 날짜로 ~/projects/agent-orchestration/daily/YYYY-MM-DD.md 파일을 열어라.
   - 파일이 없으면 TEMPLATE.md 를 참고해서 새로 만들어라.
   - `### 완료` 섹션에 `- [x] [우선순위] 항목명 #카테고리` 형식으로 추가해라.

3. **완료 메시지 출력**
   - "완료: [항목명] → ✓ SCHEDULE.md + daily" 형식으로 출력.
