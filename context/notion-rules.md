# Notion 워크스페이스 운영 규칙

> ROUTING_TABLE.md에서 분리 (2026-03-18)

**404 오류의 주원인: 잘못된 토큰 사용.** page_id를 받으면 아래 순서로 워크스페이스를 판별한다.

## 1단계: page_id로 판별
회사 워크스페이스 page_id (COMPANY_NOTION_TOKEN 필요) → **회사 워크스페이스** (`notion-company`)
그 외 모든 page_id → **개인 워크스페이스** (`notion-personal`)

## 2단계: 404 발생 시 폴백
```
notion-personal로 시도 → 404 → notion-company로 재시도
notion-company로 시도 → 404 → notion-personal로 재시도
두 번 다 404 → page_id 자체가 잘못됨, 사용자에게 확인 요청
```

## 쓰기 권한 규칙 (절대 원칙)
| 워크스페이스 | 토큰 | 읽기 | 쓰기 |
|---|---|---|---|
| 개인 (개인 Notion) | PERSONAL_NOTION_TOKEN | ✅ | ✅ |
| 회사 (Planby) | COMPANY_NOTION_TOKEN | ✅ | ❌ 절대 금지 |

**Gemini**: `notion-personal`만 연결됨 → 회사 워크스페이스 접근 불가 (의도적 설계)

## ⚠️ 실전 주의사항 (2026-03-06 테스트 검증)

**claude.ai MCP ≠ notion-personal MCP (별개 통합)**
- `mcp__claude_ai_Notion__*` 도구 = claude.ai 웹앱 전용 통합 → 접근 가능 페이지가 다름
- `notion-personal` MCP / `notion_db.py` = PERSONAL_NOTION_TOKEN 기반 → 별도 통합
- 같은 개인 워크스페이스라도 claude.ai MCP에서 404가 날 수 있음
- **claude.ai MCP 404 시**: notion_db.py 또는 REST API(PERSONAL_NOTION_TOKEN)로 재시도

**notion_db.py create는 커스텀 속성 설정 불가**
- `--title`만 지원. 상태·날짜·선택 등 DB 속성 설정 불가
- DB 항목 속성(status, select 등)까지 써야 할 때 → **REST API 직접 호출**
```bash
curl -s -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer $PERSONAL_NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{"parent": {"database_id": "..."}, "properties": {...}}'
```

**도구별 Notion 접근 능력 정리**
| 도구 | 페이지 읽기 | 페이지 쓰기 | DB 속성 쓰기 | 표 생성 |
|---|---|---|---|---|
| claude.ai MCP | 통합 연결된 페이지만 | ✅ | ✅ | ✅ |
| notion-personal MCP | PERSONAL_TOKEN 연결 페이지 | ✅ | ✅ | ✅ |
| notion_db.py | ✅ | ✅ (텍스트/마크다운) | ❌ | ❌ |
| REST API (curl) | ✅ | ✅ | ✅ | ✅ |
