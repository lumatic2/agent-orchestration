# AI 오케스트레이션 슬라이드 생성 브리프 v2

## 목표
AI 오케스트레이션 시스템 소개용 HTML 슬라이드 12개 생성.
출력: `~/Desktop/ai-orchestration-slides.html` (덮어쓰기)
완료 후: `bash ~/Desktop/agent-orchestration/scripts/render-slides.sh ~/Desktop/ai-orchestration-slides.html ai-orchestration-slides`

---

## 슬라이드 스펙
- 크기: 1280×720px (height 고정, min-height 금지 — AP-04)
- 테마: dark (#0A0E1A 배경, #00D4FF cyan 강조, #7C3AED 보조 purple)
- 폰트: 'Malgun Gothic', 'Noto Sans KR', sans-serif
- 이모지 금지 — SVG 아이콘만
- 레이아웃: A/B/C 패턴 혼합 (연속 동일 금지)

## 전역 필수 CSS (반드시 포함)

```css
@page { size: 1280px 720px; margin: 0; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Malgun Gothic', 'Noto Sans KR', sans-serif; width: 1280px; background: #0A0E1A; }
.slide { width: 1280px; height: 720px; overflow: hidden; position: relative; page-break-after: always; }

/* AP-13 한국어 어절 단위 줄바꿈 */
h1, h2, h3, .title, .headline, .slide-title {
  word-break: keep-all; overflow-wrap: break-word; text-wrap: balance;
}
p, li, .desc, .sub, .card-text { word-break: keep-all; overflow-wrap: break-word; }

/* AP-12 배지 */
.badge {
  display: inline-block; width: fit-content;
  border: 1.5px solid #00D4FF; border-radius: 6px;
  padding: 4px 12px; font-size: 11px; letter-spacing: 0.08em; color: #00D4FF;
}
```

## AP 규칙 필수 적용

- **AP-04**: .slide { height: 720px } 고정. min-height / height:100vh 절대 금지.
- **AP-08**: position:absolute 패널 내부에 반드시 display:flex; flex-direction:column; justify-content:center 적용.
- **AP-10**: 콘텐츠 높이가 슬라이드 60% 이하면 justify-content:flex-start + padding-top:80px 사용.
- **AP-11**: content-fill 직계 자식 컨테이너에 flex:1; min-height:0 추가.
- **AP-12**: 배지에 반드시 display:inline-block.
- **AP-13**: 전역 CSS에 word-break:keep-all 포함.
- **AP-15**: 카드 수에 맞는 열 수 (6카드→3열, 4카드→4열).
- **AP-17**: 다크 배경 선/구분선은 배경 대비 40% 이상 밝게.

---

## 슬라이드 내용 (12개)

### S1 — 표지 (Pattern C: title_left_panel)
- 좌 패널(35%, rgba(0,212,255,0.08) bg):
  - 소제목(12px, #00D4FF): PERSONAL AI SYSTEM
  - 메인 제목(38px bold, white): AI 오케스트레이션 시스템
  - 하단(13px, #ffffff60): 2026.03
- 우 패널(65%, #0A0E1A):
  - 배지: ARCHITECTURE OVERVIEW
  - 부제(22px bold): 멀티 에이전트 기반 자동화 아키텍처
  - SVG 아이콘 리스트 4개: Claude Code(오케스트레이터) / Codex(코드 워커) / Gemini(리서치 워커) / Queue 기반 태스크 관리

### S2 — 왜 오케스트레이션인가 (Pattern A: icon_card_grid, 3카드 1행)
- 배지: MOTIVATION
- 제목(32px): 단일 AI의 한계를 넘어서
- 카드 3개 (grid-template-columns: repeat(3,1fr)):
  1. 단일 AI 한계 — 컨텍스트 소모 / 토큰 비용 / 전문성 부재
  2. 역할 분담 — 판단(Claude) / 코드(Codex) / 리서치(Gemini)
  3. 자동화 루프 — 판단→위임→검토→기록

### S3 — 3-Layer 아키텍처 (Pattern B: asymmetric_panel)
- 배지: ARCHITECTURE
- 제목: 3계층 구조
- 좌(35%): 히어로 숫자 '3' (80px, #00D4FF) + 'LAYERS' (24px)
- 우(65%): 계층 리스트 3개 (구분선으로 분리):
  - LAYER 1 — ORCHESTRATOR: Claude Code (claude-sonnet-4-6)
  - LAYER 2 — WORKERS: Codex (코드) | Gemini (리서치)
  - LAYER 3 — TOOLS: Notion MCP | Slack MCP | GitHub | Telegram

### S4 — 의사결정 흐름 (Pattern A, 번호 리스트 2열)
- 배지: ROUTING
- 제목: 7단계 라우팅 규칙
- 2열 번호 리스트 (01~07, 번호 #00D4FF):
  01. 5분/1-3파일 → Claude 직접
  02. 순수 리서치 → Gemini
  03. 코드(5+파일) → Codex
  04. 리서치+소규모 → Claude+Gemini
  05. 분석+대규모 → Claude+Codex
  06. 리서치+대규모 → Full orchestration
  07. 사용량 한계 → 단독 위임
- 하단 강조 박스(#00D4FF 테두리): '판단은 Claude, 실행은 Workers'

### S5 — Self-Execution Guard (Pattern A: 테이블)
- 배지: GUARD
- 제목: Self-Execution Guard
- 부제(14px, #ffffff80): 실행 전 임계값 체크 — 위반 시 즉시 위임
- 테이블 (3열: 조건 / 액션 / 대상, 헤더 #00D4FF/10% bg):
  | 50줄+ 코드 작성 | → 위임 | Codex |
  | 4개+ 파일 수정 | → 위임 | Codex |
  | 100줄+ 문서 분석 | → 위임 | Gemini |
  | 리서치 필요 | → 우선 위임 | Gemini |
  | 1-3파일 간단 수정 | → 직접 처리 | Claude |
- 하단(12px, #ffffff60): 올바른 순서: 태스크 수신 → 규모 추정 → 위임 결정 → 실행

### S6 — Claude Code 역할 (Pattern C: right_accent_panel)
- 배지: ORCHESTRATOR
- 제목: Claude Code
- 좌(72%): SVG 체크 아이콘 + 역할 리스트 5개:
  - 태스크 분석 및 범위 추정
  - 에이전트 라우팅 결정
  - 결과 검토 및 통합
  - SHARED_MEMORY 업데이트
  - MCP 직접 제어 (Notion, Slack)
- 우 패널(28%, rgba(0,212,255,0.08) bg):
  - 히어로: claude-sonnet-4-6 (모노스페이스)
  - 태그: Max Plan

### S7 — Workers 비교 (Pattern A: two_card)
- 배지: WORKERS
- 제목: Codex vs Gemini
- 좌 카드 (border: #7C3AED):
  - 헤더: Codex
  - 역할: 코드 생성/수정/테스트
  - 모델: gpt-5.3-codex
  - 강점: Full-auto / 파일 편집 / 테스트 루프
  - 쿼터: 가장 넉넉 (기본 위임)
- 우 카드 (border: #00D4FF):
  - 헤더: Gemini
  - 역할: 리서치/문서 분석
  - 모델: gemini-2.5-flash
  - 강점: 1M 컨텍스트 / 웹 검색
  - 쿼터: Flash 1500/day · Pro 100/day

### S8 — 컨텍스트 관리 (Pattern A: 3카드)
- 배지: CONTEXT
- 제목: 컨텍스트 = 에이전트의 기억
- 카드 3개 (각 파일 아이콘 + 파일명 + 설명):
  1. CLAUDE.md — 행동규칙 / 라우팅기준 / 위임기준 / MCP설정
  2. SHARED_MEMORY.md — 세션 간 공유기억 / 프로젝트현황 / 핵심결정
  3. TODAY_TASKS.md — 일일 태스크 / 완료추적 / 세션연속성
- 하단(14px, #00D4FF): 컨텍스트 품질 = 에이전트 출력 품질

### S9 — 훅 & 스킬 (Pattern A: two_card)
- 배지: SYSTEM
- 제목: 훅(Hook) & 스킬(Skill)
- 좌 카드 — Hooks (border: #7C3AED):
  - PreToolUse/Bash → guard.sh 위험명령 차단
  - PreToolUse/WebSearch → Gemini 리다이렉트
  - PostToolUse/Bash → bash_audit.log 자동기록 ★신규
- 우 카드 — Skills (border: #00D4FF):
  - /hwpx — 한글 문서 생성/편집
  - /frontend-design — UI 설계
  - /commit — Git 자동화
  - + 커스텀 스킬 확장 가능

### S10 — Queue 시스템 (Pattern A, flow 레이아웃)
- 배지: QUEUE
- 제목: Queue-First 워크플로우
- 가로 플로우 (화살표 연결, 노드는 원형 — AP-18):
  [queued] → [dispatched] → [completed]
                ↓
            [stale] → [resume]
- 하단 명령어 카드 4개 (2×2 grid, 모노스페이스):
  --boot: 세션시작 큐스캔
  codex/gemini "task": 위임
  --status: 현황확인
  --resume: 실패 재시도

### S11 — 실전 프로젝트 (stat_trio: 3 카드 1행)
- 배지: PROJECTS
- 제목: 현재 운영 중인 프로젝트
- 카드 3개 (상단 숫자/아이콘 + 프로젝트명 + 설명):
  1. 투자봇
     KIS + Alpaca 자동매매
     Telegram 명령/알림
     dry-run → 실전 연결 중
  2. Luma3 포트폴리오
     Next.js / Vercel 배포
     luma3-portfolio.vercel.app
  3. 전자책
     멀티 에이전트 오케스트레이션
     자동 빌드 시스템 구현 중

### S12 — 마무리 (Pattern C: full_accent_bg 변형)
- 배경: #0A0E1A, 좌상단 장식 사각형(#00D4FF, opacity:0.15)
- 소배지: CURRENT STATUS
- 메인(52px bold, #00D4FF): Prototype → Real Projects
- 상태 지표 3개 (가로, 구분선):
  ✓ E2E 테스트 완료 (2026-02-27)
  ◎ 실전 적용 진행 중
  ◑ 완성도 ~50%
- 하단(16px, #ffffff50): 판단하는 AI, 실행하는 AI, 기억하는 AI — 셋이 하나로

---

## Codex 완료 후 자가검증 (grep으로 확인 후 완료 선언)

```bash
python3 -c "
import re
html = open('/root/Desktop/ai-orchestration-slides.html').read()
slides = html.count('class=\"slide\"')
h720 = html.count('720px')
wbreak = html.count('word-break')
badge = html.count('inline-block')
print(f'slides: {slides} (expect 12)')
print(f'height 720px: {h720} (expect 1+)')
print(f'word-break: {wbreak} (expect 1+)')
print(f'inline-block: {badge} (expect 1+)')
"
```
