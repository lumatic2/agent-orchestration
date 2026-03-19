오늘의 브리핑을 시작한다. 다음 파일들을 MCP로 읽어라:

1. `mcp__obsidian-vault__read_note("30-projects/schedule/SCHEDULE.md")`
2. `mcp__obsidian-vault__read_note("30-projects/schedule/BACKLOG.md")`
3. `mcp__obsidian-vault__read_note("30-projects/schedule/SOMEDAY.md")`
4. `mcp__obsidian-vault__read_note("30-projects/schedule/RECURRING.md")` (없으면 건너뜀)

아래 형식으로 출력해라:

---

**[오늘 날짜, 요일]**

**마감 임박**
- `## 마감 있음 (Deadline)` 섹션 항목 전체 출력
- 날짜 태그(`03-13`, `03-24` 등)를 파싱해 D-day 계산 후 앞에 표시
  - D-0 또는 초과: 🔴 D-0 (또는 D+n)
  - D-1 ~ D-3: 🔴 D-n
  - D-4 ~ D-7: 🟡 D-n
  - D-7 초과 또는 날짜 없음(다음 주, 미정): ⚪ 날짜 그대로

**오늘 (Today)**
- SCHEDULE.md `## 오늘 (Today)` 섹션 항목 출력
- 비어 있거나 완료 항목만 있으면 "아직 설정 안 됨" 출력

**오늘의 반복 항목**
- RECURRING.md가 있으면: 오늘 요일에 해당하는 항목 출력
- RECURRING.md가 없으면: 이 섹션 생략

**추천 포커스 (3개)**
- BACKLOG.md에서만 선정 (마감·Today 섹션 제외)
- 선정 기준 (순서대로 적용):
  1. 오늘이 평일이면 #회사/#개발 우선, 주말이면 #라이프/#크리에이티브 우선
  2. [높] → [중] → [낮] 순
  3. 동점이면 목록 위쪽(앞에 있는) 항목 우선
- 각 항목 아래 이유 한 줄

**Someday 힐끗보기**
- SOMEDAY.md에서 카테고리별 1개씩, 총 3개만 랜덤하게 꺼내서 보여줌
- 형식: `[카테고리] 항목명` — 한 줄 코멘트 (지금 당장 안 해도 되지만, 언젠가 할 것들)
- 목적: 아이디어가 묻히지 않도록 가끔 눈에 띄게

---

마지막에 한 마디: 오늘 컨디션이나 방향에 대한 짧은 코멘트 (1-2문장).
