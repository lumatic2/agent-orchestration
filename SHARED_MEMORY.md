> 📦 archived sections → `SHARED_MEMORY_ARCHIVE.md` (Active Projects / Recent Decisions / POSCO 사례)

# Shared Memory

> Managed by the orchestrator (Claude Code).
> All agents read this for cross-session context.
> Updated after each significant task completion.

---

## 냉장고를 부탁해 (ingredient-bot) — 개인 프로젝트 (2026-03-13~)

**경로**: `~/ingredient-bot/`
**스택**: Python, Telegram Bot API, SQLite, FastAPI+Jinja2 웹 UI, Gemini Flash
**핵심 목표**: "사람들이 식재료 낭비 없이 살 수 있게 돕는 서비스" — 스마트 냉장고가 없는 99% 가정 대상

### 로드맵 (이 방향을 향해 개선)
```
지금 (개인용)     →   6개월 (가족)      →   1~2년 (확장)      →   그 이후
텔레그램 봇           어머니 가구 실사용      멀티유저 구조           SmartThings API 연동
+ 웹 UI               → 가족 공유            카카오톡 채널 검토       또는 B2B/인수 기회
(싱글유저)             → 진짜 피드백 수집      앱 설치 불필요 강화
```
**다음 즉각 행동**: 어머니 가구에 봇 연결 (설정 대신 해드리고 텔레그램으로만 사용)

### 현재 구현 기능 (2026-03-14 기준)
**텔레그램 봇**
- 재고 CRUD, 영수증/바코드 OCR, 자연어 입력 ("달걀 5개 추가")
- `/count` 실지재고조사법 (배치 입력), `/minstock` 품목별 기준, `/low` 즉시 액션 버튼
- alias 자동 통합 (Gemini + difflib 선처리), 레시피 추천, 유통기한 자동 추정
- 하단 메뉴 키보드 (📦재고 / 🛒쇼핑 / 🍳레시피 / 📊현황 / 📸사진등록)
- 아침 알림: 긴급/주의 섹션 분리, 이모지, 날짜/요일, 웹 링크 포함

**웹 UI** (`~/ingredient-bot/web.py`, FastAPI)
- `/` 대시보드, `/inventory` 재고목록(인라인 편집·취향토글), `/shopping` 쇼핑리스트
- `/analytics` ABC분류 + EOQ 권장주문량 차트, `/barcode` 카메라 스캔
- PWA 설정, 다크모드, ngrok 외부 접근

**비용 최적화**
- suggest_canonical: difflib 선처리 → 불확실한 경우만 단일 배치 Gemini 호출
- 모델: gemini-1.5-flash (suggest_canonical, recipe) / gemini-2.5-flash (OCR 비전만)

### 차별화 포인트 (경쟁사 대비)
- 앱 설치 불필요 (텔레그램 + 웹)
- 정밀 수량 관리 + 소진 예측 (타 앱 없음)
- EOQ/ABC 물류이론 적용 (개인용 앱 중 유일)
- 한국어 영수증 OCR + alias 자동 통합
- 자연어 입력 (무비용 regex)

---

## Planby ICP 확정 (2026-03-13)

### 2-트랙 ICP

**트랙 A — 자동화 아웃바운드 (Clay + lemlist)**
- 대상: 건설·건축 관련 **중소기업 대표 (CEO)**
- 회사 유형: 건설 시공사, 건축 설계사, 부동산 개발사, 건설 IT·AI 기업 (직원 10~200명)
- Pain: 건축 AI 도입 필요하나 자체 개발 역량 없음. 범용 AI 한계 체감.
- 트리거: 새 AI 프로젝트 착수, 경쟁사 AI 도입 인지 시점
- 근거: 대표 발언("중소 건설사 CEO 아웃리치") + 넷폼알앤디 대표 직접 계약 패턴

**트랙 B — Enterprise 직접 영업 (인맥·인바운드)**
- 대상: 건설 대기업·대형 부동산 서비스사의 **AI·디지털전략 담당 임원**
- 회사 유형: 건설 대기업 계열사, 글로벌 부동산 서비스사 (삼성 E&A, CBRE 급)
- 영업 방식: 기존 레퍼런스 확장, 콘텐츠 인바운드, CES·세미나 (Clay 아웃리치 대상 아님)
- 현재 파이프라인: 현대리바트, LG전자 Nurturing 중
- 근거: Won 매출 94%가 커스텀 모델·건설 섹터에서 발생

**계약 구조 (공통)**: PoC 1,500만원(4~6주) → 커스텀 모델 납품 5천만~1.5억원

---

## 시스템 업데이트 (2026-03-14)
- **Gemini 리서치 → vault 자동 저장**: `orchestrate.sh gemini` 실행 시 결과가 자동으로 `~/vault/10-knowledge/research/`에 저장됨 (--vault 플래그 불필요). 도메인 지정 시 `--vault gtm` 등 사용.
- **슬래시 커맨드 크로스 디바이스 동기화**: `claude-code-setup` 레포(`github.com/Mod41529/claude-code-setup`)로 관리. `~/.claude/commands/`는 심링크. 새 디바이스 세팅: `git clone git@github.com:Mod41529/claude-code-setup.git && ./install.sh`
- **book-journal.md**: `~/projects/agent-orchestration/book-journal.md` — "AI는 회계사를 대체할 수 있을까?" 책 원고 재료. `/session-end` 시 자동 3줄 추가.

## Personal Task Management System (2026-03-13)

**Source of truth**: `C:/Users/1/Desktop/agent-orchestration/SCHEDULE.md`
**반복 항목**: `RECURRING.md` (같은 폴더)
**언젠가 아이디어**: `SOMEDAY.md` (같은 폴더) — 당장 실행 불필요, 주간 리뷰 때 언제든으로 승격 검토
**일일 로그**: `daily/YYYY-MM-DD.md`
**세션 요약**: `session.md`

**SCHEDULE.md 구조** (3-섹션)
- `## 오늘 (Today)` — 오늘 할 것 (MIT 원칙, 최대 3~5개 권장)
- `## 마감 있음 (Deadline)` — 날짜 태그(`03-24` 등) 포함 항목만
- `## 언제든 (Anytime)` — 카테고리별 활성 백로그 (#회사 #개발 #학습 #크리에이티브 #라이프)

**SCHEDULE.md 상태 마커**
- `- [ ]` 대기 / `- [/]` 진행 중 (다른 세션) / `- [x]` 완료
- `[/]` 항목은 `/today` 추천 포커스에서 제외됨

**슬래시 커맨드**
- `/today` — 오늘 브리핑: 마감 임박(D-day) → Today → 반복 항목 → 추천 3개(언제든) → Someday 힐끗보기 3개
- `/done 항목명` — 완료 처리 + daily 로그 기록
- `/filter 카테고리` — 카테고리 필터
- `/weekly-review` — 주간 회고 (SOMEDAY.md 승격 검토 포함)
- `/session-end` — 세션 마무리: daily 로그 → SCHEDULE.md → session.md → book-journal.md → git commit+push (~/projects/* 전체 스캔)
- `/github-trends` — 최신 GitHub 트렌드 브리핑 + TOP 3 적용 추천

**모바일 대시보드 (M1)**
- 실행 중: `~/dashboard/dashboard-server.py` (port 8765)
- 접근: `http://100.114.2.73:8765` (Tailscale) 또는 `http://192.168.200.164:8765` (LAN)
- SCHEDULE.md 읽기/완료 처리 가능, `마감 있음` + `오늘` 섹션 표시

> Codex/Gemini: 태스크 위임 전 SCHEDULE.md 참고해서 현재 진행 중인 프로젝트 컨텍스트 확인 가능.

**Notion 간트 차트**
- 페이지 ID: `30785046-ff55-8028-b0a9-ff0b5488330c`
- DB ID: `30785046-ff55-81bc-b093-dfbd85d74ac5`
- 접근: `PYTHONIOENCODING=utf-8 python C:/Users/1/notion_db.py` (PERSONAL_NOTION_TOKEN 필요)

---

## 슬라이드 생성 시스템 (Living System)

**상태**: 실사용 검증 완료. AP-01~09 누적.
**핵심 파일**: `~/projects/agent-orchestration/slides_config.yaml`
  - html_layout_patterns: Pattern A/B/C 정의 + CSS 예시
  - html_anti_patterns: AP-01~09 (원인·증상·수정 코드)
  - base_template, color_policy, proposal_template 포함
**렌더 파이프라인**: HTML → `render-slides.sh` → Playwright → PDF → ~/Desktop/
**검증된 주제**: 개vs고양이, 미쉐린서울, 치앙마이골프, 스포츠난이도, AI에이전트B2BSaaS
**AP 현황** (slides_config.yaml에 상세 기록):
  - AP-01: flex column 자식 height:100% → flex:1; min-height:0
  - AP-02: 고정 height wrapper → flex:1; min-height:0
  - AP-03: justify-content:center + flex:1 공존 → Pattern B 전환
  - AP-04: min-height/height:100vh → height:720px 고정
  - AP-05: 좁은 컬럼 긴 텍스트 → font-size 11px 이하
  - AP-06: 바 차트 width 임의 설정 → value/max*100% 공식
  - AP-07: 컬러 오버라이드 시 파스텔 사용 → 원색 유지
  - AP-08: Pattern C 패널 내부 flex centering 미적용 → justify-content:center 필수
  - AP-09: 사례박스 absolute bottom 고정 → flex 흐름 안에 margin-top:20px
**다음 슬라이드 주제**: 빈지노 vs 이센스 힙합 비교 (Gemini 리서치 진행 중, 2026-03-06)

## Planby 온보딩 패키지 (2026-03-10 완성)

## 2026-03-08 오케스트레이션 실전 검증 기록

### 검증된 패턴
- **Gemini 리서치 병렬 디스패치**: 3개 태스크 동시 → 각 5~10분 내 완료. 효과적.
- **Codex 단일 파일 생성**: vbt_backtest.py, video_creator.py — 명확한 brief + 완료 기준 필수.
- **노션 MCP vs notion_db.py**: MCP는 회사 워크스페이스만. 개인 워크스페이스는 notion_db.py 필수.
- **M1 헤드리스 자동화**: OpenClaw → SSH → Windows/MacBook Air 완전 작동. launchd로 스케줄 등록.

### 새로 구축된 시스템
- **content-automation**: GitHub Mod41529/content-automation (private)
  - Gemini 2.5 Flash로 콘텐츠 생성 (무료, 1,500 req/일)
  - YouTube OAuth 완료 (`credentials/youtube_token.json`)
  - M1 launchd 등록: 화/목/토 10:00 자동 실행
  - ⏳ MoviePy 영상 생성 모듈 (T058 Codex 작업 중)
- **investment-bot**: VectorBT 백테스팅 레이어 추가 (`vbt_backtest.py`)
  - 삼성전자 모멘텀 최적값: fast=30, slow=80 (+423%, Sharpe 1.52)

### SSH 전체 연결 현황 (2026-03-08 완성)
| 연결 | 방식 | alias |
|---|---|---|
| MacBook Air → Windows | Tailscale (100.103.17.19) | `ssh windows` |
| Windows → MacBook Air | Tailscale (100.87.7.85) | `ssh macair` |
| M1 → Windows | LAN (192.168.200.200) | `ssh windows` |
| M1 → MacBook Air | LAN (192.168.200.104) | `ssh macair` |
| Windows → M1 | LAN (192.168.200.164) | `ssh m1` |
| ↔ M4 | Tailscale 미설치 | 회사 방문 후 |

### 설치된 도구 (Windows)
- lazygit (alias: lg), fzf, Ruff, Poetry, VectorBT, google-genai
- Ruff Claude Code 훅: Edit/Write 시 .py 자동 린트

### API 키 현황
- Gemini API: aistudio.google.com (무료 Flash 1,500/일)
- YouTube OAuth: credentials/youtube_token.json (M1 + Windows)
- Moonshot/Kimi: ~/.zshrc MOONSHOT_API_KEY (M1, OpenClaw 사용)

---

## Active Projects

**목적**: 플랜바이 신입 온보딩 프로그램 설계 → 노션 + 대표 제안 슬라이드

### 완성된 Notion 페이지 (개인 워크스페이스 > 플랜바이 업무)
- **Part A** (담당자용): https://www.notion.so/Part-A-31f85046ff5581eaad80eda74a4adefe
  - 설계 원칙 / 4단계 로드맵 / 90일 성공 프로파일 / Stage 0 체크리스트(전날 D-1 포함)
  - Day 1 운영 가이드 / 대표 비전 세션 아젠다 / 버디 제도 / 피드백 루프
  - **온보딩 실패 신호 & 개입 가이드** (Early Warning 5가지 + 개입 방법)
- **Part B** (신입사원용): https://www.notion.so/Part-B-31f85046ff5581bb8e86c24cbeb8b8d8
  - 0. 입사 전 준비 (계정/서류/보안) / 1. 회사 이해 (미션·창업스토리·사업영역)
  - **플랜바이 문화 코드** (대표 DM 가능, 실수 공유, 의견 불일치 문화)
  - 팀 구조 / 도구 / 일하는 방식 (Slack 에티켓·의사결정 3단계) / Plana 써보기
  - 온보딩 체크리스트 Day 1→Week 1→Week 2→Day 30→**Day 60**→Day 90
  - 30-60-90일 플랜 (목표/완료기준/주요액션 3열 테이블) / 용어집
  - **10. FAQ** (근태·복지·업무·도구 10개 Q&A)

### 다음 작업: 온보딩 패키지 제안 슬라이드
- **목적**: 대표에게 이 온보딩 프로그램 도입을 제안하는 슬라이드 덱
- **핵심 메시지**: 현재 가이드(4개 섹션) → 신규 패키지로 업그레이드, 기대 효과
- **슬라이드 구성 (안)**:
  1. 표지: "플랜바이 온보딩 패키지 v1"
  2. 문제 정의: 지금 온보딩의 빈틈 (기존 가이드 한계)
  3. 솔루션 개요: Part A(운영자) + Part B(신입) 구조
  4. 핵심 차별점 5가지 (맥락 제공 / Day 1 경험 / 성공 기준 / 문화 코드 / 실패 감지)
  5. 90일 로드맵 타임라인
  6. 기대 효과 (적응 속도, 이탈 리스크 감소, 운영 비용 절감)
  7. 실행 계획 (즉시 적용 가능한 체크리스트)
- **슬라이드 시스템**: `render-slides.sh` 사용, slides_config.yaml AP 참조
- **새 세션에서**: `orchestrate.sh codex "온보딩 패키지 제안 슬라이드" planby-onboarding-slides` 로 위임

## Planby 자동 콘텐츠 시스템 (2026-03-10 완성)

**목적**: 건설/부동산 업계 뉴스·인사이트 자동 생성 → Notion 검토 → 홈페이지 발행

### 현재 완성된 기능 (v1)
- 스크립트: `~/Desktop/agent-orchestration/scripts/planby-content.sh`
- 실행: `bash planby-content.sh` (인자 없이 실행 → 요일 자동 로테이션)
- 스케줄: Mac mini cron `0 9 * * 1,3,5` (월·수·금 오전 9시)
- Notion DB: `31b85046ff558181b24cd5b94f371c75` (개인 워크스페이스)
  - 컬럼: 제목/카테고리/상태/생성일/뉴스출처/슬러그/메타설명/태그
- llms.txt 템플릿: `~/Desktop/planby-llms.txt` (사이트 루트에 배치 예정)
- 히스토리: `~/Desktop/agent-orchestration/data/planby-title-history.txt`

### 콘텐츠 로테이션
- 월요일 → 주간뉴스 (주간 건설/부동산 뉴스 라운드업)
- 수요일 → 인사이트 (단일 이슈 심층 분석)
- 금요일 → Q&A (실무자 질문 답변)

### 기술 스택 (무비용)
- 뉴스 수집: Google News RSS (`urllib` + `xml` 파싱, 외부 라이브러리 없음)
- 글 생성: Gemini 2.5 Flash CLI (`--yolo` 모드, 기존 $20/mo 플랜)
- 검토: Notion DB (초안 → 검토완료 → 발행됨)
- 발행: 수동 업로드 (사이트 미완성 상태)

---
### 사이트 완성 후 업그레이드 로드맵

#### Phase 2 — 자동 발행 (사이트 완성 직후)
| # | 기능 | 방법 | 난이도 |
|---|---|---|---|
| A | **Notion → 사이트 자동 발행** | Notion DB 상태 "발행됨" 변경 시 Vercel 자동 빌드 트리거. nobelium/nextjs-notion-starter-kit 방식. | 중 |
| B | **Schema.org 자동 삽입** | 발행 시 `BlogPosting` 구조화 데이터 자동 추가 → Google/AI 크롤러 최적화 | 소 |
| C | **llms.txt 배포** | `~/Desktop/planby-llms.txt`를 사이트 루트(/)에 배치 | 소 |
| D | **Unsplash 썸네일** | 키워드 기반 무료 이미지 자동 첨부 (Unsplash API 무료 플랜) | 소 |

#### Phase 3 — 인프라 고도화 (선택적)
| # | 기능 | 방법 | 난이도 |
|---|---|---|---|
| E | **GitHub Actions 이전** | Mac mini 의존성 제거. GitHub repo에서 cron으로 실행. 전용 `planby-site` repo 생성 필요 | 중 |
| F | **SEO 키워드 선행 분석** | Google Trends RSS로 이번 주 핫 키워드 먼저 파악 후 Gemini에 주제 제공 | 소 |
| G | **Slack 검토 알림** | 초안 생성 시 Slack 웹훅으로 알림 → 버튼 클릭으로 승인/반려 | 중 |

#### GitHub Repo 생성 타이밍
- **지금 아님** — 사이트 미완성 상태에서 repo 만들 이유 없음
- **사이트 완성 직전** — `planby-site` 또는 `planby-content` repo 생성
  - 포함할 것: planby-content.sh, llms.txt, GitHub Actions 워크플로, Notion DB 스키마 문서
  - agent-orchestration과 분리: 회사 팀원 공유 가능한 독립 repo

## Planby 회사 데이터 지도 (COMPANY_NOTION_TOKEN 사용)

### 워크스페이스 진입점
- Wiki: d1160001-f128-419a-ac02-25d59e48db3f (연혁, 팀원, 가이드 — 재무 데이터 없음)
- Dashboard: 2df0ef18-d41a-8011-ac83-d653081208ad (KPIs, Tasks, Squads, 미팅 기록)
- DB 허브: af1b1893-4176-4cd9-9fe3-fe4839429277 (핵심 — 고객사/모델/프로덕트)
- 투자사: ed34acc2-d85d-47b3-9deb-973ca8fb3767

### 핵심 데이터베이스 ID
| DB | ID | 용도 |
|---|---|---|
| 고객사 DB | 1ca0ef18-d41a-804b-85a9-c3021962b03f | 고객사 Tier 1-4, N_maint 추정 |
| 담당자 DB | 2770ef18-d41a-804b-abbb-e19b27164886 | 고객사 담당자 |
| 고객사 미팅 기록 | 1e40ef18-d41a-805e-8954-e95eff2014ce | 딜 흐름 단서 |
| Model DB | 1cd0ef18-d41a-80de-94da-cb87bfa3af2e | Custom Engine 모델 현황 |
| KPIs | 2df0ef18-d41a-81bf-80b4-de7c35cc3d61 | 매출/운영 KPI |
| AI & SaaS Request | 2a00ef18-d41a-80f0-bd25-fafef0e9bbe5 | SaaS 요청 현황 |
| Planby 계정 현황 | 2df0ef18-d41a-80f4-8f94-c05f9e798f46 | 유지보수 계약 수 추정 |
| 통합 미팅 기록 | 30f0ef18-d41a-8169-9150-c698ce5a27a4 | 딜/운영 기록 |

### 탐색 우선순위 (입력값 레지스트리 기준)
1. 고객사 DB → 계약 건수, N_maint, Tier 분류
2. KPIs → 매출·마진 수치
3. Planby 계정 현황 → 유지보수 계약 수
4. 통합 미팅 기록 → 딜 흐름·병렬 캐파 단서

### 접근 방법
- Claude Code: COMPANY_NOTION_TOKEN으로 Notion 직접 접근 가능
- Google Drive: claude.ai 웹에서만 접근 가능 (MCP 미설치)
- 대용량 분석 시: Gemini에 위임 (DB ID 지정해서 효율화)

## Planby 재무·세무 분석 (2026-03-05 진행 중)

### Notion 페이지 (개인 워크스페이스)
| 페이지 | ID | 상태 |
|---|---|---|
| 📊 재무 기반 다지기 (메인) | 31a85046ff55818f9b92eafa260805aa | ✅ 완료 |
| 📋 세무사 체크리스트 | 31a85046ff5581298337e2c988c2c9f1 | ✅ 완료 (2026-03-05 R&D/고용세액공제 추가) |
| 💰 세제 혜택 분석 | 31985046ff5581739709c5bbdaf57bc4 | ✅ 완료 |
| ✅ 할 일 목록 | 31985046ff5581aaa386cbf9dfd24bac | ✅ 완료 |
| 🚨 CEO 런웨이 현황 보고 | 31a85046ff5581278c06c638d1026376 | ✅ 완료 (2026-03-05 신규) |

### 핵심 발견
- 현금 잔고 (3/5 추정): ~1.86억 / 월 소진: ~9,000만
- **런웨이 수정**: 5월 초 위기 → 2026-03-31 TIPS 5억 입금 후 ~6.86억 → 2026년 11~12월
- TIPS R&D 총 15억 (24.09~27.08) / 지급 일정: 1차 2024-12(완료), 2차 2025-03(완료), **3차 5억 2026-03-31(26일 후)**, 4차 2027-03
- 1~2월 지원금 급감 원인 확인: 각 연차 지급 예정일이 3월 말이라 1~3월이 공백 (타이밍 문제, 이상 없음)
- 2월 급여 급증: 26.01 AI 연구 1명 신규 채용
- 장기차입금 4.5억 (만기일 미확인)
- MRR 사실상 0, 매출 대부분 B2B 일회성 프로젝트
- 2024 R&D 세액공제 42.85백만 이월 중

### ~~AnythingLLM 플랜바이 워크스페이스~~ (2026-03-12 사용 중단 — 기록 보존)
- API Key: planby-cb99f5222e56c3ed40d98c77e35bf001
- 조회 스크립트: ~/projects/agent-orchestration/scripts/planby_ask.sh (워크스페이스 자동 라우팅)
- 업로드 스크립트: ~/projects/agent-orchestration/scripts/planby_upload.sh
  - `bash planby_upload.sh <파일>` — 자동 분류 업로드
  - `bash planby_upload.sh <파일> <워크스페이스>` — 수동 지정
  - `bash planby_upload.sh --list` — 워크스페이스별 문서 수 확인

**워크스페이스 slug 매핑**
| 워크스페이스 | slug | 용도 |
|---|---|---|
| 플랜바이 기준 문서 | 0fb026cf-455b-40b9-911e-33ba8c63dbaa | 계약서, 정책, 운영기준, 공식 스펙 |
| 플랜바이 재무, 세무 | 51656bcc-e741-4e16-8094-4c813fe259bf | 재무제표, 세무신고, 결산, 회계 |
| 플랜바이 전략, 영업 | 0e6792e6-bc20-4e49-9d24-91af61bbf5fb | 전략, 영업, 고객, OKR, 가격 |
| 플랜바이 회의, 초안 | 497efbac-31d9-4864-8d53-98a49437d51e | 회의록, 초안, 메모, 검토 문서 |
| 플랜바이 (전체/구) | 4b7216ef-9bb1-4553-a2b0-0478a73d5b03 | 분류 불명확 시 fallback |

### ~~AnythingLLM 운영 규칙~~ (deprecated)

**워크스페이스 분리 기준**
| 워크스페이스 | 용도 |
|---|---|
| 기준 문서 | 최종 정책, 공식 스펙, 계약서, 운영 기준 (FINAL 문서) |
| 재무, 세무 | 재무제표, 세무신고서, 결산 자료, 회계 관련 |
| 전략, 영업 | 제안서, 고객 요구사항, FAQ, 가격 정책, OKR |
| 회의, 초안 | 회의록, 초안, 아이디어 메모, 검토 문서 (DRAFT) |

**문서명 규칙**: `YYYY-MM-DD_주제_vN_STATUS.md`
- STATUS: `FINAL` / `DRAFT` / `ARCHIVE`
- 예: `2026-03-05_Pricing_Policy_v2_FINAL.md`
- 구버전은 삭제 말고 Archive 워크스페이스로 이동

**코드 vs 문서**: 코드 자체는 AnythingLLM 대신 레포 검색. 코드 설명 문서만 업로드.

컨텍스트 팩 형식 → SHARED_PRINCIPLES.md AnythingLLM Integration Rules 참조

### 확인된 B2B 파이프라인 (2026-03-05 회사 Notion 조회)
- Won 고객사: HK건축(ARR 288만/년 Pro Yearly 2025.09~2026.09), 지안건축설계(서면계약완료 금액미기재)
- 주요 딜: 삼성E&A 재계약(SE&A v1.0.0-RC1 개발 중), CNP동양 RFI자동화(KPI 35%), Plana 재런칭(16.5%)
- KPI Sales Actual 전부 0 → MRR 사실상 제로

### 미완료 — 자료 수령 후 처리
1. TIPS R&D 협약서 → 2026년 집행금액·타이밍 확인 → 런웨이 재계산
2. 장기차입금 계약서 → 만기일·상환조건 확인
3. 2026년 1월 지급수수료 4,489만원 내역 → 반복 여부 확인
4. 삼성 E&A 재계약 협상 현황 파악 (계약 시 런웨이 즉시 개선)

## 기기별 시스템 가용성 (2026-03-10 기준)

| 시스템 | Mac mini (주) | Windows PC | 비고 |
|---|---|---|---|
| Claude Code + MCP | ✅ | git pull → sync.sh | notion/figma MCP 별도 등록 필요 |
| Obsidian vault MCP | ✅ (로컬) | ✅ (SSH→M1) | `obsidian-vault` MCP 등록 완료: Windows/M1/M4/MacBook Air |
| AnythingLLM RAG | ~~✅ localhost:3001~~ ❌ 사용 중단 | ❌ | 수치 오류로 제거. PDF 직접 Read로 대체 |
| Google Drive (개인) | ✅ 마운트됨 | ❓ 확인 필요 | ~/Library/CloudStorage/ |
| Google Drive (회사) | ✅ 마운트됨 | ❓ 확인 필요 | steven.jun@planby.us |
| Figma MCP | ✅ (재시작 필요) | ❌ | launchd + npm 설치 필요 |
| law_search.py | ✅ | ✅ git pull 후 | Gemini CLI 필요 |

### SSH 접속 정보 (2026-03-10 전수 확인 완료)

| 별칭 | IP (Tailscale) | 사용자 | SSH 키 | SCP | 비고 |
|---|---|---|---|---|---|
| mini | 100.114.2.73 | luma2 | ~/.ssh/id_ed25519 | ✅ | 이 Mac Mini |
| m4 | 100.100.79.12 | luma3 | ~/.ssh/id_ed25519 | ✅ | |
| macair | 100.87.7.85 | luma2 | ~/.ssh/id_ed25519 | ✅ | |
| windows | 100.103.17.19 | 1 | ~/.ssh/id_ed25519 | ✅ | cmd.exe 기본 셸. 바탕화면: `Desktop\` |

```bash
# 파일 전송 예시
scp /path/to/file.pdf windows:Desktop/file.pdf
scp /path/to/file mini:/path/to/dest
ssh windows "dir Desktop"
```

### OpenClaw 파이프라인 (2026-03-10)

**구조**: 텔레그램 → OpenClaw(라우터) → Claude Code → 작업 수행 → 결과 텔레그램 전송

- OpenClaw 설정: `~/.openclaw/openclaw.json`
- 주 모델: `moonshot/moonshot-v1-32k` (라우팅용), fallback: `kimi-k2.5`
- Claude Code 위임 방식: `delegate_to_claude` 툴 → `claude --dangerously-skip-permissions "작업"`
- 완료 알림: `openclaw system event --text "Done: 요약" --mode now`

**슬라이드 파이프라인** (`scripts/slides-bridge.sh`):
1. `gen-brief.sh` → 브리프 생성
2. `orchestrate.sh gemini` → Gemini 리서치
3. `orchestrate.sh codex` → Codex HTML 생성
4. `render-slides.sh` → Playwright → PDF
5. `scp` → 대상 기기 전송 (Windows: `windows:Desktop/파일명.pdf`)
6. `telegram-send.sh` → 텔레그램 전송

```bash
# 슬라이드 생성 예시 (로컬 저장)
bash scripts/slides-bridge.sh "커피" 10 local

# 텔레그램으로 직접 전송
bash scripts/slides-bridge.sh "커피" 10 telegram
```

### 새 기기/세션 셋업 순서
```bash
git pull
bash scripts/sync.sh            # settings, guard, adapters 배포

# Claude Code — Notion MCP
claude mcp add --scope user notion-personal -- npx -y @notionhq/notion-mcp-server
claude mcp add --scope user notion-company  -- npx -y @notionhq/notion-mcp-server

# Gemini CLI — Notion MCP (조사+저장 원스톱용)
PERSONAL_NOTION_TOKEN=$(printenv PERSONAL_NOTION_TOKEN)
gemini mcp add --scope user --trust \
  -e "OPENAPI_MCP_HEADERS={\"Authorization\": \"Bearer ${PERSONAL_NOTION_TOKEN}\", \"Notion-Version\": \"2022-06-28\"}" \
  notion-personal npx -y @notionhq/notion-mcp-server

# 환경변수: PERSONAL_NOTION_TOKEN, COMPANY_NOTION_TOKEN → ~/.zshenv
# AnythingLLM: 별도 설치 후 scripts/planby_ask.sh의 API key 재생성 필요

# Obsidian vault MCP (M1이 아닌 기기)
python3 -c "
import json, os
path = os.path.expanduser('~/.claude.json')
config = json.load(open(path)) if os.path.exists(path) else {}
config.setdefault('mcpServers', {})['obsidian-vault'] = {
    'type': 'stdio', 'command': 'ssh',
    'args': ['m1', 'source ~/.nvm/nvm.sh && npx -y @bitbonsai/mcpvault@latest ~/vault']
}
json.dump(config, open(path, 'w'), indent=2)
print('obsidian-vault MCP added')
"
```

## 에이전트 확장 (2026-03-05)

### 이미지 생성 에이전트
- 스크립트: `scripts/image_agent.sh "요청" [--type 로고|캐릭터|마케팅|콘셉트] [--ratio 1:1|16:9|3:4]`
- 페르소나: `agents/image_persona.md`
- DALL-E 3 / Midjourney / SD 프롬프트 동시 생성 → ChatGPT 핸드오프
- Ollama SD 모델 설치 시 자동으로 직접 생성 전환

### 전문직 AI 에이전트
- 범용 스크립트: `scripts/expert_agent.sh [doctor|lawyer|tax] "질문" [--pro]`
- 페르소나 폴더: `agents/experts/` (doctor.md, lawyer.md)
- 새 전문가 추가: `agents/experts/[이름].md` 생성만 하면 자동 인식
- `bash expert_agent.sh list` 로 목록 확인

### 영상 편집 자동화 (FFmpeg)
- 스크립트: `scripts/video_edit.sh [trim|merge|resize|gif|thumb|audio|speed|caption|ai]`
- FFmpeg 없어도 `ai "질문"` 으로 명령어 생성 가능
- 설치: `brew install ffmpeg`

### 콘텐츠 파이프라인 (소설/책/논문)
- 스크립트: `scripts/content_pipeline.sh [init|write|compile|status|list]`
- 페르소나: `agents/content_persona.md`
- 인테이크: `templates/intake_content.md`
- 프로젝트 저장 위치: `~/Desktop/content-projects/[프로젝트명]/`
- 추가 비용 없음 (Gemini Flash 사용)

### 회계사 AI 에이전트
- 스크립트: `scripts/tax_agent.sh "질문" [--planby] [--pro]`
- 페르소나: `agents/accountant_persona.md` (조특법 R&D/고용세액공제, TIPS 회계처리 전문)
- 인테이크: `templates/intake_accounting.md`
- `--planby`: AnythingLLM 플랜바이 문서 컨텍스트 포함
- `--pro`: Gemini 2.5 Pro 사용 (심층 분석)
- 추가 비용 없음 (Gemini Pro 구독 내)

## GitHub 트렌드 자동 수신 시스템 (2026-03-12)

- **스크립트**: `~/Desktop/agent-orchestration/scripts/github-trends.sh`
- **실행**: `bash github-trends.sh` (전체 파이프라인) / `--dry-run` (미리보기)
- **스케줄**: macOS launchd `com.luma3.github-trends` — 매주 월 09:00 자동 실행
- **흐름**: `gh api` 수집 (최근 7일 ★기준) → Gemini 분류 → 리포트 저장 → 텔레그램 알림
- **리포트**: `reports/github-trends-YYYY-MM-DD.md` (즉시적용/참고/스킵 분류)
- **텔레그램**: 즉시적용 5개 + 이유 + 적용 포인트 + 하단 "Claude Code 붙여넣기" 명령어
- **적용 방법**: 텔레그램 명령어 복사 → Claude Code에 붙여넣기 or `/github-trends` 실행

**버그 수정 (2026-03-12)**: `is_rate_limited()` false positive
- 원인: Codex가 작업 중 `orchestrate.sh` 읽을 때 파일 내 "rate limit" 주석이 매칭됨
- 수정: 출력 전체 대신 마지막 30줄만 검사하도록 변경

## Slack ↔ Claude Code 봇 프로젝트 (2026-03-13 진행 중)

**목적**: 플랜바이 팀 전체가 Slack에서 Claude Code를 사용 — 문서·슬라이드 생성, 회사 데이터 조회, 업무 자동화
**방식**: SDK 방식 (`@anthropic-ai/claude-code`), API 호출 아님

### 레포 & 경로
- **레포**: `~/projects/claude-code-slack-bot/` (원본: mpociot/claude-code-slack-bot)
- **npm install**: ✅ 완료
- **버그 수정**: `claude-handler.ts` 65행 하드코딩 경로 → `import.meta.url` 기반으로 수정

### 완료된 설정 파일
| 파일 | 상태 | 내용 |
|---|---|---|
| `.env` | ⚠️ Slack 토큰 빈칸 | ANTHROPIC_API_KEY 입력됨, BASE_DIRECTORY 설정됨 |
| `mcp-servers.json` | ⚠️ COMPANY_NOTION_TOKEN 필요 | notion-company + obsidian-vault 설정 |
| `templates/templates.yaml` | ✅ 완료 | 슬라이드 2종 + 문서 3종 템플릿 매니페스트 |
| `CLAUDE.md` | ✅ 완료 | 회사 컨텍스트 + Notion DB ID + 생성 규칙 |

### company-vault 초기 구축
- **경로**: `~/company-vault/` (재무, 계약, 정책, 고객사, 회의록)
- **초기 문서**: `재무/2026-03-05_런웨이-분석.md`, `고객사/고객사-현황.md`

### 봇 실행 명령어
```bash
NODE24="v24.14.0"
export PATH="$HOME/.nvm/versions/node/$NODE24/bin:$PATH"
cd ~/projects/claude-code-slack-bot
unset CLAUDECODE ANTHROPIC_API_KEY
npm run dev
```

### 완료된 설정
- Slack 토큰 3개 `.env`에 입력 완료
- Node v24.14.0 필수 (v25는 CLI 호환 오류)
- `@anthropic-ai/claude-code` v1.0.128으로 업데이트
- `permissionMode: bypassPermissions` (permission 팝업 없음)
- DM에서 thread 없이 새 메시지로 답장
- DM 세션 키 안정화 (ts 제거 → 메시지마다 새 세션 방지)
- `SLACK_BOT=1` 환경변수 → 글로벌 CLAUDE.md의 --boot 스킵
- `BASE_DIRECTORY=/Users/luma2/projects/claude-code-slack-bot/`

### 남은 작업
1. **COMPANY_NOTION_TOKEN** → `mcp-servers.json`에 입력
2. **Phase 2**: Google Workspace MCP 추가, company-vault 확장
3. **Phase 3**: 슬라이드·문서 HTML 템플릿 실제 작성

### Slack App Manifest (앱 생성 시 붙여넣기)
```yaml
display_information:
  name: Claude Code Bot
  description: AI-powered assistant using Claude Code SDK
  background_color: "#4A154B"
features:
  bot_user:
    display_name: Claude Code
    always_online: true
oauth_config:
  scopes:
    bot:
      - app_mentions:read
      - channels:history
      - chat:write
      - chat:write.public
      - im:history
      - im:read
      - im:write
      - users:read
      - reactions:read
      - reactions:write
      - files:read
settings:
  event_subscriptions:
    bot_events:
      - app_mention
      - message.im
      - member_joined_channel
  interactivity:
    is_enabled: true
  socket_mode_enabled: true
```

### 아키텍처 요약
```
Slack 메시지 → Slack Bot (Socket Mode, Mac mini)
  → Claude Code SDK 프로세스
  → MCP: notion-company, obsidian-vault, (google-workspace 예정)
  → 로컬: company-vault, templates, slides_config.yaml
  → 결과를 Slack에 응답
```

## Known Issues

_Tracked here when agents encounter blockers._

## 실전 사례: POSCO 제안서 (2026-03-06)

### MCP 작업은 위임 불가 — 직접 실행 원칙
Notion/Slack 등 MCP 도구가 필요한 작업은 Codex/Gemini에 위임 불가 (MCP 접근 권한 없음).
위임 결정 전 체크: "이 작업에 MCP가 필요한가?" → YES면 Claude 직접 실행.

### Notion API 실전 한계
- 블록 100개/요청 한도 → 초과 시 400 에러 → `append_paragraphs`에 chunk_size=100 청킹 적용
- `notion_db.py` 버그 수정 완료: `_looks_like_markdown` 루프 내 early return 오류

### 제안서 AI 지원 패턴 (비즈니스)
1. **익명화**: 고객사명 → "도메인 전문사" (예: 넷폼알앤디 → 건축 도메인 전문사)
2. **현학적 표현 3계층**: 제목(추상 개념어) / 도표(기술 용어 RAG·Embedding) / 본문(평이한 언어)
3. **수혜자 중심 리프레이밍**: "타사 납품 사례" 뉘앙스 → "귀사 전용 구조" 프레이밍

### 긴 세션 컨텍스트 관리
- `/tmp/` 파일을 버전별 중간 저장소로 활용 (posco_v5_slim.md → posco_v6.md)
- 컨텍스트 압축 발동 전 SHARED_MEMORY 업데이트가 연속성 핵심

## 통합 지식베이스 (2026-03-12)

**경로**: `~/Desktop/knowledge-base/`
**목적**: Claude가 파일을 복사하지 않고 링크/ID로 원본에 직접 접근하는 인덱스 시스템

### 소스별 접근 방법

| 소스 | 방법 | 비고 |
|------|------|------|
| 회사 Notion | `NOTION_TOKEN=$COMPANY_NOTION_TOKEN python3 ~/notion_db.py` | 읽기 전용 |
| 로컬 PDF | Claude `Read` 도구 직접 사용 | `~/Desktop/플랜바이 자료/` |
| Clobe.AI Excel | Python `openpyxl` 직접 파싱 | 랜딩존: `플랜바이 재무:세무 정보/Clobe.AI 엑셀 파일/` |
| Google Drive | MCP `search_drive_files` (yusung8307@gmail.com) | 온디맨드 검색 |
| 대용량 멀티문서 | `orchestrate.sh gemini` 위임 | 1M 컨텍스트 활용 |
| Obsidian | `~/knowledge-vault/` 직접 Read | claude-logs, notes, projects |

### 인덱스 파일
- `notion-company-index.md` — 회사 Notion 100개 페이지 PAGE_ID
- `local-files-index.md` — 로컬 파일 전체 (기본정보/재무세무/고객사/영업/분석)
- `drive-guide.md` — Drive 검색 가이드
- `obsidian-guide.md` — Obsidian vault 구조

### ⚠️ AnythingLLM 사용 중단 (2026-03-12)
수치 오류 문제로 제거. PDF → Claude 직접 Read, Excel → Python 파싱으로 대체.
(API Key, 워크스페이스 정보는 하단 섹션에 기록 보존)

---

## Google Workspace MCP (2026-03-12)
- **MCP 이름**: google-workspace (taylorwilsdon/google_workspace_mcp)
- **설치 방법**: `uvx workspace-mcp --single-user` (stdio transport)
- **인증**: OAuth 토큰 `~/.google_workspace_mcp/credentials/yusung8307@gmail.com.json`
- **client_secret**: `~/.config/gws/client_secret.json`
- **배포 완료**: Windows / M1 / M4 / MacBook Air 4대 동일 설정
- **가능한 작업** (114개 도구):
  - Gmail: 읽기/쓰기/검색/발송/라벨 관리
  - Google Calendar: 일정 조회/생성/수정 + Google Meet 링크 포함
  - Google Drive: 파일 읽기/쓰기/공유
  - Google Docs/Sheets/Slides: 문서 읽기/편집
  - Google Tasks/Contacts/Forms/Chat
- **대표 시나리오**: 캘린더 조회 → 시트 데이터 추출 → 이메일 발송 → Meet 일정 생성을 한 번의 프롬프트로 자동화 가능
- **gws CLI**도 별도 설치됨 (npm, v0.11.1): 터미널에서 직접 API 호출 가능
