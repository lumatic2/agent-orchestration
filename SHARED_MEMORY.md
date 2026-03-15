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
| 슬라이드 생성 시스템 | `context/slides-system.md` | 실사용 중 — AP-09까지 누적 |
| content-automation | MEMORY.md 참조 | launchd 실행 중 (화/목/토 10:00) |

---

## System Quick Reference

- **태스크 관리**: `SCHEDULE.md` (Today / Deadline / Anytime)
- **오케스트레이션 사용법**: `orchestrate.sh schema --json`
- **기기 SSH·설정**: `context/system-setup.md`
- **Knowledge Vault**: `luma2@m1:~/vault/` (MCP: `obsidian-vault`)
- **슬라이드**: `context/slides-system.md` + `slides_config.yaml`
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

- **2026-03-15**: GitHub 트렌드 적용 — nah 보안가드, claude-statusline, brief.md Context Budget/Stop Triggers, progress.md 자동생성, `--status --json`, `schema --json` 확장, SHARED_MEMORY 구조 개선
- **2026-03-14**: Gemini 리서치 → vault 자동 저장 (--vault 불필요)
- **2026-03-12**: Google Workspace MCP 4대 배포, GitHub 트렌드 자동 수신 시스템
- **2026-03-08**: E2E 오케스트레이션 실전 검증 완료 (SSH·content-automation·VectorBT)
