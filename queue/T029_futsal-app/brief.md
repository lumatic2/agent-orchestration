# Task: 풋살 성장 앱 (Futsal Growth App) — Next.js Prototype

## Goal
풋살 실력을 단계별로 키울 수 있는 웹 앱. 커리큘럼 로드맵, YouTube 강의 큐레이션, 개인 기록 트래킹을 MVP로 구현.

## Tech Stack
- Framework: Next.js 14 (App Router)
- Styling: Tailwind CSS + shadcn/ui
- State/Progress: localStorage (DB 없음)
- Video: YouTube embed iframe (API key 없음, 영상 ID 하드코딩)
- Deploy: Vercel (vercel.json 포함)

## Design
- 다크 테마: 배경 #0a0a0a, 카드 #141414
- 포인트: green-500 (#22c55e)
- 폰트: Inter
- 스포티하고 모던 (Nike Training 느낌)

## Pages
1. / — 홈: 내 레벨, 오늘의 미션 카드, 전체 진행률바, 빠른 이동 버튼
2. /curriculum — 초급/중급/고급 탭, 4주x3세션 구성, 세션 완료 체크
3. /lessons — 패스/드리블/슈팅/수비/체력 탭, YouTube 카드 + 모달 embed
4. /progress — 완료 세션 수, 주간 달력, 도넛 차트(SVG), 스트릭

## Data (하드코딩)
- /data/curriculum.ts: 초급/중급/고급 각 4주, 주당 3세션, 세션당 드릴 3개
- /data/lessons.ts: 카테고리별 YouTube 실제 영상 ID (실제 풋살 강의 영상)

## localStorage
- futsal_level: beginner | intermediate | advanced
- futsal_completed: string[] (session IDs)
- futsal_streak: { lastDate, count }

## Components
LevelBadge, SessionCard, VideoCard, VideoModal, ProgressRing(SVG), WeekCalendar

## File Structure
futsal-app/
  app/ layout.tsx, page.tsx, curriculum/page.tsx, lessons/page.tsx, progress/page.tsx
  components/ (6개)
  data/ curriculum.ts, lessons.ts
  lib/ storage.ts
  tailwind.config.ts, vercel.json, package.json

## Output
- ~/Desktop/futsal-app/ 에 전체 프로젝트 생성
- npm install && npm run build 통과 확인

## Done Criteria
- 홈→커리큘럼→완료→진행률 반영 플로우 동작
- 강의 카드 클릭→모달 YouTube 재생
- 새로고침 후 진행률 유지
- npm run build 에러 없음
- 모바일 반응형
