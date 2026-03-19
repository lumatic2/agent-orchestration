$ARGUMENTS 카테고리에 해당하는 항목만 SCHEDULE.md에서 필터링해서 보여줘.

1. `mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")` 로 읽어라.
2. #$ARGUMENTS 태그가 붙은 항목만 추출해라.
3. 진행 중 / 시작 전으로 나눠서 출력해라.
4. 없으면 "해당 카테고리 항목 없음" 출력.

사용 가능한 카테고리: 회사, 개발, 학습, 크리에이티브, 라이프, 노션
예: /filter 회사
