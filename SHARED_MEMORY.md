# Shared Memory

> Managed by the orchestrator (Claude Code).
> All agents read this for cross-session context.
> Updated after each significant task completion.

---

## Active Projects

- **MOD**: 54-card thinking framework deck. v1=thought frameworks, v2=knowledge/memory, v3=agents/physical AI.
- **Planby Pilot**: Business Strategy & Finance. OKR-ROI-Decision structures.
  - 현재 작업: Planby Management Architecture v1.0 (4주 계획, 2주차 완료 · 3주차 시작 예정)
  - **세션 인수인계 페이지** (다음 세션 시작 시 반드시 먼저 읽기): https://www.notion.so/31a85046ff5581b58b6cf4a171319da1
  - 3주 계획 전체: https://www.notion.so/3-v2-31485046ff55803585c3eef798679f75
  - 임원 브리핑 (5개 확인 항목): 31885046-ff55-81ca-975a-cbc72a4b1af3
  - **다음 할 일**: 임원 인터뷰 후 레지스트리 업데이트 → Week 3 (Revenue Architecture + GTM Structure 1p씩)
  - **핵심 발견**: Base 시나리오 10.1억 (18억의 56%) / 마진율 불일치(50% vs 22~28%) / 원가 시스템 없음
  - **⚠️ notion_db.py 주의**: replace-content를 자식 페이지 있는 페이지에 쓰면 자식 페이지 아카이브됨. 복구: curl PATCH /v1/pages/{id} {"archived":false}

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
| 📋 세무사 체크리스트 | 31a85046ff5581298337e2c988c2c9f1 | ✅ 완료 |
| 💰 세제 혜택 분석 | 31985046ff5581739709c5bbdaf57bc4 | ✅ 완료 |
| ✅ 할 일 목록 | 31985046ff5581aaa386cbf9dfd24bac | ✅ 완료 |

### 핵심 발견
- 현금 잔고 (3/5 추정): ~1.86억 / 월 소진: ~9,000만 / 런웨이: 5월 초
- TIPS R&D 총 15억 (24.09~27.08), 1~2월 지원금 급감은 집행 타이밍 문제 가능성
- 2월 급여 급증: 26.01 AI 연구 1명 신규 채용
- 장기차입금 4.5억 (만기일 미확인)
- MRR 사실상 0, 매출 대부분 B2B 일회성 프로젝트
- 2024 R&D 세액공제 42.85백만 이월 중

### AnythingLLM 플랜바이 워크스페이스
- API Key: planby-cb99f5222e56c3ed40d98c77e35bf001
- Workspace Slug: 4b7216ef-9bb1-4553-a2b0-0478a73d5b03
- 65개 문서 임베딩 (로컬 PDF 24개 + 개인 Drive 2개 + 회사 Drive 6개)
- 조회 스크립트: ~/Desktop/agent-orchestration/scripts/planby_ask.sh

### 미완료 — 자료 수령 후 처리
1. TIPS R&D 협약서 → 2026년 집행금액·타이밍 확인 → 런웨이 재계산
2. 장기차입금 계약서 → 만기일·상환조건 확인
3. 2026년 1월 지급수수료 4,489만원 내역 → 반복 여부 확인
4. 확정 수주 계약 목록 → B2B 파이프라인 정리
5. CEO 런웨이 현황 보고

## Recent Decisions

- **2026-02-27**: E2E orchestration test passed. Gemini researched (argparse recommended) → Codex generated code → Claude verified. Full pipeline working. Note: Gemini `--sandbox` removed (requires Docker).

## Conventions

_Populated as project patterns emerge._

## 기기별 시스템 가용성 (2026-03-05 기준)

| 시스템 | Mac mini (주) | Windows PC | 비고 |
|---|---|---|---|
| Claude Code + MCP | ✅ | git pull → sync.sh | notion/figma MCP 별도 등록 필요 |
| AnythingLLM RAG | ✅ localhost:3001 | ❌ 미설치 | 기기별 별도 설치 + 문서 재업로드 |
| Google Drive (개인) | ✅ 마운트됨 | ❓ 확인 필요 | ~/Library/CloudStorage/ |
| Google Drive (회사) | ✅ 마운트됨 | ❓ 확인 필요 | steven.jun@planby.us |
| Figma MCP | ✅ (재시작 필요) | ❌ | launchd + npm 설치 필요 |
| law_search.py | ✅ | ✅ git pull 후 | Gemini CLI 필요 |

### 새 기기/세션 셋업 순서
```bash
git pull
bash scripts/sync.sh            # settings, guard, adapters 배포
claude mcp add --scope user notion-personal -- npx -y @notionhq/notion-mcp-server
claude mcp add --scope user notion-company  -- npx -y @notionhq/notion-mcp-server
# 환경변수: PERSONAL_NOTION_TOKEN, COMPANY_NOTION_TOKEN → ~/.zshenv
# AnythingLLM: 별도 설치 후 scripts/planby_ask.sh의 API key 재생성 필요
```

## Known Issues

_Tracked here when agents encounter blockers._
