# Session Log

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
