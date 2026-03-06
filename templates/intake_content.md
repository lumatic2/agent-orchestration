# 콘텐츠 프로젝트 인테이크

## 필수 정보

| 항목 | 내용 |
|---|---|
| **프로젝트명** | (파일명으로 사용 — 공백 없이) |
| **유형** | 소설 / 책 / 논문 |
| **주제/설명** | (1-3문장) |
| **챕터 수** | (원하는 챕터 수, 없으면 AI 자동 결정) |
| **독자 대상** | |
| **언어** | 한국어 / English |

## 실행 순서

```bash
# 1. 목차 생성
bash ~/Desktop/agent-orchestration/scripts/content_pipeline.sh init "프로젝트명" 소설 "주제"

# 2. 챕터 순서대로 작성 (번호 없으면 자동으로 다음 챕터)
bash ~/Desktop/agent-orchestration/scripts/content_pipeline.sh write "프로젝트명"

# 3. 전체 합치기
bash ~/Desktop/agent-orchestration/scripts/content_pipeline.sh compile "프로젝트명"

# 진행 현황 확인
bash ~/Desktop/agent-orchestration/scripts/content_pipeline.sh status "프로젝트명"
```

## 결과물 위치
`~/Desktop/content-projects/[프로젝트명]/`
- `outline.md` — 목차
- `chapters/ch01.md`, `ch02.md`, ... — 각 챕터
- `compiled.md` — 최종 합본
