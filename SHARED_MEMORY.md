> 📦 상세 컨텍스트 → `context/` 디렉토리 | 아카이브 → `SHARED_MEMORY_ARCHIVE.md`

# Shared Memory

> Managed by the orchestrator (Claude Code).
> All agents read this for cross-session context.
> 프로젝트 상세 작업 시 → `context/[project].md` 로드할 것.

---

## [RULE] Vault → SHARED_MEMORY 승격 기준

vault에 쌓인 리서치를 SHARED_MEMORY로 올리는 기준:

| 승격 O | 승격 X |
|---|---|
| 에이전트 라우팅 결정에 영향 (모델 선택, 툴 선택) | 특정 주제 단순 조사 결과 |
| 반복 실수 방지 (API 한계, 버그 패턴) | 일회성 프로젝트 리서치 |
| 여러 세션에 걸쳐 참조할 시스템 설계 결정 | 트렌드/뉴스 (빠르게 낡음) |

승격 방법: `context/` 파일 또는 SHARED_MEMORY 해당 섹션에 직접 기록. vault 원본은 그대로 유지.

---

## [RULE] API 키 직접 호출 금지 (전 에이전트 적용)

**규칙**: Gemini API, OpenAI API 등 외부 API 키를 사용자 승인 없이 직접 호출 금지.

**올바른 우선순위**:
1. Claude Code (MCP 도구, 내장 기능)
2. Gemini CLI (`orchestrate.sh gemini`)
3. Codex CLI (`orchestrate.sh codex`)
4. API 직접 호출 → **반드시 "API를 N회 호출합니다. 진행할까요?" 확인 후**

---

## Active Projects

| 프로젝트 | 컨텍스트 파일 | 상태 |
|---|---|---|
| ingredient-bot (냉장고를 부탁해) | `context/ingredient-bot.md` | 개발 중 — 어머니 가구 연결 대기 |
| Planby (ICP·온보딩·콘텐츠·재무) | `context/planby.md` | 진행 중 — TIPS 3차 2026-03-31 |
| Slack ↔ Claude Code 봇 | `context/slack-bot.md` | 설정 중 — COMPANY_NOTION_TOKEN 필요 |
| 슬라이드 생성 시스템 | `context/slides-system.md` | **Option B 완성** — `bash scripts/slides.sh "주제" 9` |
| content-automation | MEMORY.md 참조 | launchd 실행 중 (화/목/토 10:00) |
| law-automation | `context/law-automation.md` | 파이프라인 완성 — M1 배포 + 법제처 API 승인 대기 |

---

## System Quick Reference

- **태스크 관리**: `SCHEDULE.md` (Today / Deadline / Anytime)
- **오케스트레이션 사용법**: `orchestrate.sh schema --json`
- **기기 SSH·설정**: `context/system-setup.md`
- **Knowledge Vault**: `luma3@m4:~/vault/` (MCP: `obsidian-vault`)
- **슬라이드**: `bash scripts/slides.sh "주제" [슬라이드수]` → Gemini JSON → inject → PDF. 9타입(title_panel/card_grid/numbered_list/bar_chart/big_statement/comparison_table/timeline/quote_close/before_after). 아이콘 24개 내장.
- **문서**: `bash scripts/docs.sh "주제" [type]` → PDF. `--word` 추가 시 DOCX도 생성. type: proposal/report/business_plan/summary/meeting. 7섹션 타입(cover/section/bullet_section/table_section/highlight_box/two_col/closing).
- **Notion 개인**: `PERSONAL_NOTION_TOKEN` / 회사: `COMPANY_NOTION_TOKEN`

---

## 검증된 운영 패턴

- **MCP 작업은 Claude 직접**: Notion/Slack MCP → Codex/Gemini 위임 불가
- **Gemini 병렬 디스패치**: 3개 동시 → 각 5~10분 완료. 효과적.
- **Codex brief 필수**: 명확한 Context Budget + Stop Triggers 없으면 삽질
- **Notion 개인 워크스페이스**: MCP 아님 → `notion_db.py` 사용
- **세션 간 컨텍스트**: 큰 프로젝트 작업 전 해당 `context/` 파일 먼저 로드

---

## Known Issues

_Tracked here when agents encounter blockers._

---

## 시스템 업데이트 로그

- **2026-03-15 (2)**: Knowledge Vault 대규모 업데이트 — 229 노트 / 25MB. 법령 36개 자동 추적(law_registry.yaml), law-check.py + M1 launchd 파이프라인 완성. pdf-to-vault.py LOCAL_VAULT_PATH 추가. 도메인: accounting(~60) / tax(21) / legal(14) / finance(14) / medical(7) / investment(3, 보강 필요)
- **2026-03-15**: GitHub 트렌드 적용 — nah 보안가드, claude-statusline, brief.md Context Budget/Stop Triggers, progress.md 자동생성, `--status --json`, `schema --json` 확장, SHARED_MEMORY 구조 개선
- **2026-03-14**: Gemini 리서치 → vault 자동 저장 (--vault 불필요)
- **2026-03-12**: Google Workspace MCP 4대 배포, GitHub 트렌드 자동 수신 시스템
- **2026-03-08**: E2E 오케스트레이션 실전 검증 완료 (SSH·content-automation·VectorBT)

## Slack Bot 개발 로드맵 (2026-03-17)
**위치**: M1 `~/projects/claude-code-slack-bot/`

### Phase 1 — MVP 안정화 (현재)
- [x] 스레드 버그 수정 (slash cmd에서 첫 메시지를 thread anchor로 확정)
- [x] QUE 템플릿 모달 구현 (`/que`, App Home 버튼)
- [ ] 신입 온보딩 패키지 (Notion → vault 이식)

### Phase 2 — 기능 고도화
1. **계정/서버**: 현재 개인 Claude Code OAuth. 정식 출시 시 회사 공용 계정 + 서버 이전
2. **뉴스 구독 시스템**: 4개 분야 일부 통합/개선 필요
3. **홈 탭 버튼 정비**: 필요한 것만 유지. 문서 작성·슬라이드 → 실제 파이프라인(slides-bridge.sh) 연동, 버그 없이 일정 품질
4. **Vault 접근 제어**: M4 vault 중 회사 파일 + 전문가 도메인만 봇에 노출 (개인 폴더 차단)
5. **신입 온보딩**: 봇과 대화로 회사 지식 습득 + 작업 방향 설정

### Phase 3 — 최적화
- 전체 코드 점검: 속도·비용·보안 개선

### 기술 현황
- Socket Mode (Bolt), Claude Code OAuth, MCP: notion-company/obsidian-vault/google-workspace
- 기존 에러: permission-mcp-server.ts 타입 에러 (pre-existing, 기능 영향 없음)

## vault-company 규칙 (슬랙 봇 접근 제어)
- 봇: `~/vault-company/` 만 접근 (mcp-servers.json)
- 개인 Claude Code: `~/vault/` 전체 접근
- 봇에 지식 추가: `ln -sf ~/vault/경로 ~/vault-company/폴더명`
- 절대 링크 금지: 00-inbox, 40-log 등 개인 폴더
- 규칙 전문: `cat ~/vault-company/README.md`
