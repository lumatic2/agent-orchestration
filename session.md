# Session Log

## [2026-03-17] (M4)
**한 일**: M4→M1 vault 파일 이동(planby 8개, copora 2개, W11 주간회고), expert-knowledge-map.md 생성, EXPERT_BASE.md 도메인 테이블 업데이트(5→9개), ChromaDB 폐기, 법제처 API 연결 완료(OC=8307) + law-check.py 버그 2개 수정 → 36개 법령 ls_id 등록·전 법령 최신 확인
**진행 중**: expert 페르소나 개별 knowledge_refs 추가, investment 도메인 보강
**주요 결정**: ChromaDB 완전 폐기(vault MD 파일로 대체), vault 쓰기는 M1 MCP만 사용
---

## [2026-03-17] (Windows)
**한 일**: session-end vault 연동(SSH→M1) + heredoc 버그 수정, boot Windows vault pull 추가, sync.sh 경로 치환 제거(~/통일), 시스템 파일 역할 치트시트 vault 저장
**진행 중**: Slack AI 에이전트 버그 안정화 (03-19 마감)
**주요 결정**: vault 원본 M1 단독, 다른 기기 pull-only / CLAUDE.md 직접 편집 금지(adapter가 원본)
---

## [2026-03-16 — it-contents / events-tracker 개선] (Mac Air)
**한 일**: 텔레그램 동향 섹션 카테고리화, TOP5→TOP3, Gemini 노이즈 필터, M1 SSH PATH 버그 수정, events-tracker cwd=/tmp 교체, 실 발송 테스트 완료
**진행 중**: 없음
**주요 결정**: events-tracker Gemini 호출은 cwd=/tmp Python subprocess로 통일 (디렉토리 스캔 hang 방지)
---

## [2026-03-16 밤 — SCHEDULE 업데이트] (Mac Air)
**한 일**: SCHEDULE.md #학습 섹션에 "석/박사 알아보고 일정 만들어보기" 항목 추가
**진행 중**: 석/박사 알아보고 일정 만들어보기
**주요 결정**: 없음
---

## [2026-03-16 저녁 — 크로스 플랫폼 동기화 시스템 정비] (Mac Air)
**한 일**: env.sh 모듈 신설 및 scripts/*.sh 전체 적용, Python 3.9 호환 자동화(ruff FA), 4기기 settings.json 표준화, ~/.claude/CLAUDE.md 글로벌 규칙 신설, sync.sh 충돌 해소, system-setup.md 현행화
**진행 중**: Slack AI 에이전트 버그 안정화 (03-19 마감), content-automation E2E 테스트
**주요 결정**: env.sh = 크로스 플랫폼 단일 진실 소스. ~/CLAUDE.md(오케스트레이션)와 ~/.claude/CLAUDE.md(글로벌 규칙) 두 파일 역할 분리 확정
---

## [2026-03-16 — slides 파이프라인 점검 + 기기 동기화] (Mac Air)
**한 일**: slides.sh(Option B) 파이프라인 구조 파악, Windows 03-14 이후 미동기화 발견 → git pull 완료, session-end 기기 레이블 기능 추가
**진행 중**: 없음
**주요 결정**: session-end에 hostname 기반 기기 식별 추가 — 이후 세션 기록에 기기명 자동 표시
---

## [2026-03-16 심야 — Nick 슬랙봇 PDF 파이프라인 시도 → ec58fdd 롤백]
**한 일**: /slide·/doc JSON→PDF 파이프라인 전환 시도(6시간), 다중 인스턴스·haiku 모델 404·DM 스레딩 버그 등 복합 장애 수습 실패, ec58fdd hard reset으로 봇 원상복구
**진행 중**: Nick 봇 PDF 파이프라인 — 내일 ec58fdd 기반에서 처음부터 재작성 (`memory/project_nick_bot_rebuild.md`)
**주요 결정**: launchd KeepAlive 기기는 launchctl로만 재시작. 로그 경로 `logs/nick-bot.log`.
---

## [2026-03-16 — 플랜바이 03-18 임원 미팅 자료 최종]
**한 일**: meeting-prep-0318.md 전체 검토 및 최종 수정 (Clay 오류 수정·EOD→목요일·빈 줄 정리); summary-0318.md 생성 (임원진 전달용 4주 성과 요약); /ui-ux-review + /decide-deal 스킬 .claude/commands/ 등록
**진행 중**: 03-18(화) 임원 미팅 진행, Slack AI 에이전트 버그 안정화 (03-19 마감)
**주요 결정**: summary-0318.md = 미팅 종료 시 임원진에게 전달하는 인계 문서로 확정
---

## [2026-03-16 — content-automation 텔레그램 메시지 정리]
**한 일**: 콘텐츠 메시지 투자봇→NewsFairy 콘텐츠 그룹채팅 라우팅 변경, 썸네일 사진 전송 제거, 블로그 알림 액션 지침 추가
**진행 중**: 월요일 저녁 content-automation E2E 테스트
**주요 결정**: 콘텐츠 관련 알림은 모두 NewsFairy_bot 유튜브/인스타 그룹채팅(-5274175959)으로 통일
---

## [2026-03-16 심야 — Public APIs Batch 2~4 + 식재료봇 버튼 버그 수정]
**한 일**: 식재료봇 키보드 버튼 버그 수정(다중인스턴스+키워드매칭), Batch2 레시피 수량/날씨 표시, Batch3 NewsAPI it-contents 연동, Batch4 Pexels 썸네일 자동화+Wikipedia→vault 도구
**진행 중**: 법제처 API 승인 확인, investment vault 보강, expert 법령 연결 점검, Slack AI 에이전트 버그 안정화(플랜바이 마감 03-19)
**주요 결정**: Edamam 건너뛰고 Gemini 강화로 대체, data.go.kr 포기, 버튼 매칭은 키워드 포함 방식으로
---

## [2026-03-15 심야6 — 포트폴리오 Business 섹션 개선]
**한 일**: works.ts에 s3(Startup Financial Intelligence)·s4(GTM Automation Pipeline)·s5(AI Consulting Delivery Framework) 추가/교체; HubSection 생산→운영 rename + 4개 패널 전면 재작성; YouTube 링크 @luma_nico 변경
**진행 중**: 포트폴리오 dev/video/music 섹션 추가 콘텐츠 보강
**주요 결정**: Business 도메인 패널 포인트에서 Planby 내부 언어 제거 → 일반화된 포트폴리오 언어로 교체
---

## [2026-03-15 심야5 — 예비창업패키지 사업계획서 Copora 최종 보강]
**한 일**: 1절 권도균 창직 인용+할루시네이션 법정 사례(Mata v. Avianca) 추가, 2-1절 자율 경영 에이전트 포지셔닝+모드1/2 2트랙+보고서/슬라이드 파이프라인+데이터 보안 추가, 2-2절~4-1절 연동 수정, 기계장치(SW) 지급수수료 편입, 표현 전면 정리
**진행 중**: 사업계획서 양식 docx 타이핑 입력 (03-21~22 주말), K-Startup 제출 (03-24 16:00)
**주요 결정**: Copora = 자율 경영 에이전트 (단순 Q&A 탈피), MVP = 신고기한 알림+파일 분석, Phase 2 = 홈택스/은행 Open API
---

## [2026-03-15 심야4 — content-automation 영상 파이프라인 완성]
**한 일**: 다크 테마+Noto Sans KR, CSS 애니메이션 영상화(12프레임), Whisper medium+단어수 기반 슬라이드 타이밍, Gemini sections 구조 개선, HTML 썸네일(Playwright), --thumbnail 플래그 추가, thumbnails().set() YouTube 자동 세팅
**진행 중**: 월요일 저녁 E2E 테스트 (Whisper medium 모델 사전 다운로드 필요)
**주요 결정**: 썸네일은 직접 제작(Canva) + --thumbnail 플래그로 경로 지정, YouTube 업로드만 자동화
---

## [2026-03-15 심야3 — Knowledge Vault + 법령 자동화 파이프라인]
**한 일**: pdf-to-vault.py 분류기 6건 패치, Vault 229노트/25MB 달성, law_registry.yaml(36법령)+law-check.py(법제처 API 자동감지)+M1 launchd 파이프라인 완성, context/law-automation.md 문서화
**진행 중**: M1 배포(law-check+plist), 법제처 API 승인 대기→OC값 추가→--discover, investment 도메인 보강(vault 3개)
**주요 결정**: 법령 자동 업데이트는 M1 launchd로 실행(항상 켜짐+vault 로컬 저장). pdf-to-vault.py LOCAL_VAULT_PATH로 Windows/M1 공용화.
---

## [2026-03-15 심야2 — 슬라이드·문서 파이프라인 완성]
**한 일**: 슬라이드 Option B 완성 (8컴포넌트+SVG 아이콘 24개+before_after, E2E 와인의역사 성공), 문서 파이프라인 구축 (7섹션 타입, 5가지 type, --word DOCX 지원), 레이아웃 버그 수정 (섹션 강제 페이지→자연 흐름)
**진행 중**: 회사소개서 docs.sh 제작, content-automation M1 git pull + dry-run
**주요 결정**: slides.sh/docs.sh SHARED_MEMORY 등록 — 다음 세션부터 자동 사용
---

## [2026-03-15 심야 — 텔레그램 알림 전수 개선]
**한 일**: 11개 알림 시스템 전수 점검 및 개선 — 투자봇(실시간 환율·장시작/마감 알림·현재가 표시), content-automation(HTML 포맷·해시태그), 식재료봇(HTML 포맷·Notion URL), /investment·/content 스킬 생성
**진행 중**: 투자봇 daily_open 09:00 KST 실제 수신 확인, content-automation --dry-run 테스트
**주요 결정**: 30분마다 포트폴리오 Telegram 알림 → silent(DB/Notion만) 변경, 장시작/마감 알림으로 대체
---

## [2026-03-15 — AI 팁 총정리 문서화]
**한 일**: vault/30-projects/ai-tips/ 전체 초안 완성(braindump→outline→draft v0.8→blog v0.2), 4장 GCP Secret Manager 심화 박스·유료 전환 타이밍·보안 섹션 개선, 마무리 수미상관 추가, 바탕화면에 MD+PDF 생성
**진행 중**: 블로그(브런치/네이버) 실제 포스팅, PDF 공유 채널 결정
**주요 결정**: 심화 내용(GCP)은 본문 격리 박스로 처리 — 비개발자 독자 이탈 방지
---

## [2026-03-15 야간 — 오케스트레이션 미활용 영역 전수 점검]
**한 일**: T115/T118 큐 정리, MoviePy v2 API 패치+push, GWS MCP 라우팅 추가, vault_check() 7일 캐시(orchestrate.sh), Gemini Pro 기준 테이블·멀티모달·spark 정교화, Nanobanana→Gemini 웹 정정, vault→SHARED_MEMORY 승격 기준 추가
**진행 중**: M1 git pull (content-automation MoviePy 패치), content-automation --dry-run 테스트
**주요 결정**: Perplexity/Grok CLI 추가 불필요 — 기존 스택 활용도 개선이 먼저. Gemini CLI 이미지 생성 불가(텍스트 전용), 이미지는 Gemini 웹 수동 생성 유지.
---

## [2026-03-15 오후 — GitHub 트렌드 오케스트레이션 적용]
**한 일**: nah 보안가드+claude-statusline 설치, task_brief.md Context Budget/Stop Triggers, progress.md 자동생성, --status --json / schema --json, SHARED_MEMORY 673→67줄 구조개선(context/ 분리), 블루프린트 시스템(slides/feature-dev/research-to-vault)
**진행 중**: 슬라이드 블루프린트 실전 테스트, OpenClaw 대시보드 패턴 적용, 동적 컨텍스트 주입
**주요 결정**: luma3 CLI 불필요 (MCP로 충분). 블루프린트는 orchestrate.sh run으로 실행.
---

## [2026-03-15 저녁 — GCP Secret Manager 기기 통합]
**한 일**: secrets_load.sh Python ADC 폴백 추가, content-automation common.py GCP SDK 연동, MacBook Air gcloud+pyenv Python 3.11 설치, M1 CLOUDSDK_PYTHON 설정, broken stitch MCP 엔트리 제거
**진행 중**: content-automation --dry-run 테스트, slide.html 디자인 검토, Instagram 파이프라인
**주요 결정**: 모든 기기에서 gcloud CLI 실패 시 Python ADC(google.auth) 폴백으로 비밀 로드. Instagram 미설정은 정상 상태.
---

## [2026-03-15 — content-automation 루마 채널 파이프라인]
**한 일**: CLAUDE.md 모델 라우팅 추가, content-automation 파이프라인 전면 재구성(HTML+Playwright 슬라이드/캐릭터 오버레이/카라오케 자막/2단계 파이프라인), nanobanana MCP gemini-2.5-flash-image 패치, API 무단 호출 방지 규칙 memory+SHARED_MEMORY 추가
**진행 중**: --dry-run 전체 파이프라인 테스트, slide.html 디자인 검토, Instagram 파이프라인
**주요 결정**: 캐릭터 이미지는 사용자가 직접 나노바나나로 생성. Gemini API 직접 호출은 사전 승인 필수.
---

## [2026-03-14 저녁 — M1 닉 봇 개선]
**한 일**: claude-code-slack-bot ANTHROPIC_API_KEY OAuth 강제 수정, Block Kit 뉴스 구독 버튼 action_id 중복 해결, ClaudeError/circuit breaker 도입, obsidian-vault nvm 충돌 수정, 다중 인스턴스 정리
**진행 중**: 봇 재시작 완료 (5:18 PM) — Slack 실테스트 결과 다음 세션에 확인
**주요 결정**: subprocess env에서 ANTHROPIC_API_KEY 완전 삭제로 OAuth 강제 (빈 문자열 X)
---

## [2026-03-14 오후 — M1]
**한 일**: events-tracker 개인/회사 분리+Slack 연동, 4개 기기 git pull 자동화, auto-stage 훅, session-end 개선, 책 주제 브레인스토밍+공통 골격 설계
**진행 중**: 책 주제 확정 — Windows 세션에서 배경 인터뷰 후 주제 선정 예정
**주요 결정**: Slack Webhook은 본인 DM으로 연결 (회사 미공개), events-tracker 매주 월 08:00 발송
---

## [2026-03-14]
**한 일**: 텔레그램 cron 미작동 수정(PATH+환경변수), @NewsFairy_bot으로 채팅방 4개 분리, IT콘텐츠 72h+중복제거, events-tracker 소스 확대+우선순위 정렬+설명 2줄, 3개 스크립트 vault 저장 추가
**진행 중**: events-tracker 실운영 결과 확인 (전국민AI경진대회 포함 여부)
**주요 결정**: 투자 포트폴리오 봇은 분리하지 않고 현행 유지
---

## [2026-03-12 오후]
**한 일**:
- OpenClaw 완전 제거 → claude-code-telegram 설치 및 설정 (E2E 테스트 완료)
- 각종 트러블슈팅: 봇 토큰 혼동, Conflict, 비용 한도, 보안 검증, Welcome 메시지 제거
- M4 원격 파일 생성 (piano.html, minesweeper.html) + git status 실행 검증

**진행 중**:
- agent-orchestration 12커밋 미푸시 상태
- claude-code-telegram 세션 간 컨텍스트 유지 개선 가능

**주요 결정**:
- OpenClaw 대체 확정. Telegram → Claude Code 직통 구조로 단순화.
---

## [2026-03-12]
**한 일**:
- Notion 간트 차트 → SCHEDULE.md 마이그레이션 (42개 항목, 카테고리 태그 포함)
- 슬래시 커맨드 5개 구축: /today, /done, /filter, /weekly-review, /session-end
- RECURRING.md, daily/ 로그 구조 생성
- git 자동 커밋 훅 추가 (settings.json), /done Notion 역방향 동기화 구현
- SHARED_MEMORY.md + MEMORY.md 정확도 수정
- 금요일 대표 미팅 준비 항목 추가 및 오늘 할 일 정리

**진행 중**:
- 금요일(03-13) 대표 미팅 자료 준비 — 노션 페이지 + 슬라이드 제작 필요
- 플랩풋볼 예약 미완료

**주요 결정**:
- 일정 관리: Notion(시각적 뷰) + SCHEDULE.md(source of truth) 하이브리드
- AI 회계법인 프로젝트는 agent-orchestration 내장 유지 (별도 레포 분리 안 함)
---
