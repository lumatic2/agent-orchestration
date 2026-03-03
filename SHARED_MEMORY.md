# Shared Memory

> Managed by the orchestrator (Claude Code).
> All agents read this for cross-session context.
> Updated after each significant task completion.

---

## Active Projects

- **MOD**: 54-card thinking framework deck. v1=thought frameworks, v2=knowledge/memory, v3=agents/physical AI.
- **Planby Pilot**: Business Strategy & Finance. OKR-ROI-Decision structures.
  - 현재 작업: Planby Management Architecture v1.0 (3주 계획, 2주차 진행 중)
  - 작업 페이지: https://www.notion.so/3-v2-31485046ff55803585c3eef798679f75
  - 2주차 페이지: https://www.notion.so/2-31485046ff55809aba98d8f8ddc42edf
  - 2주차 서브페이지: 입력값 레지스트리, 인터뷰 질문지, Strategy Architecture 초안, Revenue Hypothesis 초안

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

## Recent Decisions

- **2026-02-27**: E2E orchestration test passed. Gemini researched (argparse recommended) → Codex generated code → Claude verified. Full pipeline working. Note: Gemini `--sandbox` removed (requires Docker).

## Conventions

_Populated as project patterns emerge._

## Known Issues

_Tracked here when agents encounter blockers._
