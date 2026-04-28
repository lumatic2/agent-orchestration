<!-- USER_CONTEXT.md — 사용자 환경 정보 (위치, 로컬 도구, 데이터, 외부 시스템) -->
<!-- sync.sh 가 ~/CLAUDE.md 와 ~/AGENTS.md (Codex home) 양쪽 끝에 append 한다. -->
<!-- 직접 편집은 이 파일에서만. 두 deployed 파일은 sync.sh 가 매번 덮어씀. -->

---

## 사용자 컨텍스트

- **기본 위치**: 서울특별시 종로구 명륜3길 27 (명륜동, 성균관대 인근). 좌표 ≈ lat 37.585 / lng 126.999
  - 위치 기반 질의("내 주변", "가까운 ○○")의 기준점. 다이소·편의점·영화관 MCP 탐색 시 이 주소 사용

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI. 예: `es "*.py"` / `es ext:mp4 -sort size-descending`
  - `Error 8: Everything IPC not found` 시 본체가 user 세션에 안 떠 있는 것: `cmd //c start "" "C:\Program Files\Everything\Everything.exe" -startup`

---

## Google Workspace 로컬 도구

- **`gwx`** (`~/bin/gwx`) — Gmail/Drive/Calendar 일상 조회용 짧은 alias. `gwx mail [N]` (받은편지함) · `gwx unread` · `gwx today/tomorrow/week/upcoming` · `gwx find <q>` · `gwx read <id>` · `gwx send <to> <subj> <body>` · `gwx standup/digest/prep`. `gwx help`로 전체
- **`gws`** — 비공식 Google Workspace CLI (npm, 2026-03 출시, OAuth 완료). `mcp__claude_ai_*` connector보다 우선
  - **Helper 컨벤션**: `gws <svc> +<helper> [flags]` — gmail (`+triage` `+read` `+send` `+watch` `+reply`), calendar (`+agenda --today/--week/--days N`, `+insert`), drive (`+upload`), sheets (`+read` `+append`), docs (`+write`), workflow (`+standup-report` `+weekly-digest` `+meeting-prep` `+email-to-task`)
  - **Raw API**: `gws <svc> <res> <method> --params '<JSON>' [--format table|json|yaml|csv]` · 스키마: `gws schema <svc>.<res>.<method>` · `--dry-run` · `--page-all` (NDJSON)

---

## 로컬 데이터 자료실

- **위치**: `D:\datasets\` — 한국어/한국 데이터셋 모음 (총 ~6.3 GB)
- **인덱스**: `D:\datasets\INDEX.md` — 메인 페르소나(Nemotron-Personas-Korea 100만), KMMLU·KLUE·CLIcK 평가, lbox-open 판례, KOSIS API 추출 CSV 등 전체 카탈로그·로드 코드·라이선스
- **세션 시작 규칙**: 데이터 분석·페르소나 시뮬·통계 비교 작업 요청 시 먼저 `INDEX.md` 1회 읽고 진행
- **API 키**: `KOSIS_API_KEY`는 `D:\datasets\.env`, `DART_API_KEY`는 Windows User env (`os.environ['DART_API_KEY']`)에서 직접 로드

---

## 외부 도구 역할 분리

### Obsidian Vault — 개인 지식 저장소 (나만 봄)
- **위치**: `m4:~/vault/`. PARA × Johnny Decimal 구조, 깊이 ≤5단계
- **용도**: 리서치 원본, 세션 로그, 아이디어 메모, 학습 노트
- **경로**: 임시→`05-Inbox/` / 도메인 지식→`10-Resources/10.0X-{Cat}/` / 전문가→`20-Areas/` / 프로젝트→`30-Projects/` / 로그→`40-Logs/YYYY-MM-DD.md` / 종료→`90-Archives/`. 카테고리 매핑은 vault `00-System/VAULT_INDEX.md` (JDex)
- **쓰기**: MCP `obsidian-vault` (Claude) 또는 `ssh m4` 직접 (Codex). 로컬 clone 금지. **Area·Category 폴더에 파일 직접 저장 금지** (ID 폴더 안에만). Frontmatter 필수 (type, domain, source, date, status)
- **검증 우선**: vault 경로를 코드 변수·옛 로그에서 가져오지 말 것 — 옛 폴더(예: 사라진 `10-knowledge/`)가 박혀 있을 수 있다. 새 vault 작업 전 `ssh m4 'ls <경로>'`로 존재 검증 + 카테고리 매핑은 항상 `~/vault/00-System/VAULT_INDEX.md`(JDex)에서 확인

### Notion — 외부 공유용 대시보드 (남에게 보여줌)
- **용도**: 포트폴리오, 프로젝트 소개, 정리된 문서, 팀/외부 공유 자료
- **도구**: `notion-ext-mcp` MCP (Claude) 또는 `~/notion_db.py` 헬퍼 (Codex). 환경에 `NOTION_TOKEN`, `NOTION_DATABASE_ID` 존재 가정 (출력 금지)
- **원칙**: publish-ready 콘텐츠만. 작업 중인 초안은 프로젝트 폴더 또는 vault에
