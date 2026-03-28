# /creative — 크리에이티브 세션 허브

writing · drawing · music · convert-script을 조합해 창작 프로젝트를 진행한다.
같은 세션 안에서 스킬이 이어지므로 컨텍스트(주제·분위기·키워드)가 자동으로 흐른다.

---

## 1. 프로젝트 유형 선택

AskUserQuestion을 호출해라:
- 질문: "오늘 무엇을 만들까요?" (header: "프로젝트")
- A) 유튜브 영상 — 스크립트 → Remotion 슬라이드 변환
- B) 글쓰기 — 에세이·소설·뉴스레터·카피 등 모든 글
- C) 디자인 — 이미지 프롬프트·SVG·UI·ComfyUI 생성
- D) 음악 — Suno 프롬프트 설계

Other 선택 시 → 자유 조합 모드로 진입 (아래 참조)

---

## 2. 라우팅

### A) 유튜브 영상
1. `/writing` 실행 (유튜브 스크립트 모드로 시작)
2. 스크립트 완성 후 AskUserQuestion을 호출해라:
   - 질문: "스크립트 완성. 다음 단계를 선택하세요." (header: "다음 단계")
   - A) 슬라이드만 — /convert-script로 Remotion 슬라이드 생성
   - B) 슬라이드 + 썸네일 — 변환 후 /drawing으로 썸네일까지
   - C) 완료 — 스크립트만 사용

### B) 글쓰기
1. `/writing` 실행 — 장르·문체·플랫폼은 writing 스킬 안에서 결정
2. 완성 후 AskUserQuestion을 호출해라:
   - 질문: "글 완성. 이어서 만들 것이 있나요?" (header: "다음 단계")
   - A) 커버 이미지 — /drawing으로 이어서 (글 주제·분위기 자동 반영)
   - B) 완료

### C) 디자인
1. `/drawing` 실행
2. 완성 후 AskUserQuestion을 호출해라:
   - 질문: "이어서 만들 것이 있나요?" (header: "다음 단계")
   - A) 글쓰기 — /writing으로 이어서
   - B) 음악 — /music으로 이어서
   - C) 완료

### D) 음악
1. `/music` 실행
2. 완성 후 AskUserQuestion을 호출해라:
   - 질문: "음악 프롬프트 완성. 이어서 만들 것이 있나요?" (header: "다음 단계")
   - A) 앨범아트 — /drawing으로 이어서 (장르·분위기 자동 반영)
   - B) 완료

### Other) 자유 조합
AskUserQuestion을 호출해라 (multiSelect: true):
- 질문: "사용할 도구를 선택하세요." (header: "도구 선택")
- A) 글쓰기 — /writing
- B) 디자인 — /drawing
- C) 음악 — /music
- D) 유튜브 영상 — /writing → /convert-script

선택 순서대로 스킬 실행. 각 완성 후 다음으로 자동 전환.

---

## 3. 스킬 실행 방법

각 스킬을 실행할 때 해당 스킬 파일을 읽고 그 지시를 따른다:
- `/writing` → `~/projects/agent-orchestration/skills/writing.md`
- `/drawing` → `~/projects/agent-orchestration/skills/drawing.md`
- `/music` → `~/projects/agent-orchestration/skills/music.md`
- `/convert-script` → `~/projects/agent-orchestration/skills/convert-script.md`

세션 내 이전 결과물(제목·주제·분위기·키워드)을 다음 스킬에 명시적으로 반영한다.
