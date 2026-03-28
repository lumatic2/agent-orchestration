# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## 기본 규칙

- 한국어로 소통
- 간결하게 응답

## 모델 라우팅 규칙 (엄격 모드)

질문의 복잡도를 판단하여 현재 설정이 부적절하면 추천:

**Sonnet (오케스트레이터 판단 용도만)**
- 1-3파일, <50줄의 단순 수정만 직접 수행
- 작업: 파일 조회, 단순 편집, 위임 판단, 결과 검수
- 금지: 버그 수정, 기능 구현, 리팩토링
- 예: "README 첫 줄 수정"은 직접 수행 / "버그 고쳐줘"는 Codex 위임

**Opus (전략/시스템 설계만)**
- 사용: 오케스트레이션 아키텍처, 시스템 점검, 장기 전략
- 사용 빈도: 월 5-10회 수준으로 제한
- 절대 금지: 코드 생성, 문서 작성, 일상 판단
- 예: "토큰 절약 시스템 재설계"는 Opus / "이 task는 Codex 위임 맞나?"는 Sonnet

**Codex (코딩/분석 중심)**
- 4+ 파일, 50+ 줄, 모든 구현/리팩토링 작업 담당
- 코드 리뷰, 에러 분석, 데이터 처리 우선 담당
- 캐싱 효율 80%+ 유지가 목표이므로 최우선 활용

**Gemini (리서치/문서 분석)**
- 4개+ 소스 비교, 트렌드 분석 등 복잡 리서치 담당
- 50+ 페이지 문서 요약/분석 담당
- 배치 작업(대량 콘텐츠 수집, 크롤링) 우선 담당
- 일 1500 한도 대비 저활용 구간을 해소하도록 적극 사용
- 단순 리서치(3회 이내 검색, 단일 주제)는 Claude가 직접 처리

현재 모델이 부적절하면 세션 시작 시 한 번만 안내:
"이 작업은 [모델]이 적합해요. `/model [모델]`로 바꾸시겠어요?"

---


## Self-Execution Guard

시스템 전체 구조가 불명확할 때 → vault `00-System/SYSTEM_MAP.md` 읽어라 (MCP: `mcp__obsidian-vault__read_note("00-System/SYSTEM_MAP.md")`).

<!-- BEGIN GUARD_TABLE -->
| Condition | Action |
|---|---|
| 50+ lines of code to write | STOP → `orchestrate.sh codex "task" name` |
| 4+ files to create/modify | STOP → `orchestrate.sh codex "task" name` |
| Complex research (4+ sources, trend, crawl, 50p+ doc) | STOP → `orchestrate.sh gemini "task" name` |
| Browser/GUI/canvas/JS SPA needed | STOP → `orchestrate.sh openclaw "task" name` |
| Simple research (≤3 searches, single topic) | Proceed directly (WebSearch/WebFetch) |
| Simple edit (1-3 files, <50 lines) | Proceed directly |
<!-- END GUARD_TABLE -->

> ⚠️ **리서치 위임 방법**: 반드시 `Bash("bash ~/projects/agent-orchestration/scripts/orchestrate.sh gemini \"task\" name")` 직접 호출.
> `Agent(subagent_type="gemini-researcher")` 사용 **금지** — 위임 루프 버그로 실제 리서치를 수행하지 않음.

Examples:
- "지뢰찾기 게임 만들어줘" → Python ~100줄 → **`orchestrate.sh codex`로 위임**
- "README 첫 줄 수정" → 1파일 1줄 → 직접 수행
- "이 라이브러리 최신 버전 찾아줘" → 단순 검색 1회 → **Claude 직접 처리**
- "AI 에이전트 프레임워크 5개 비교해줘" → 복잡 리서치 → **`orchestrate.sh gemini`로 위임**
- "빗썸 시세 긁어줘" / "차트 만들어줘" / "네이버 검색해줘" → **`orchestrate.sh openclaw`로 위임**
- OpenClaw 작업 템플릿 → `~/projects/agent-orchestration/templates/handoff_openclaw.md`

상세 오케스트레이션 규칙 (Pre-flight, Multi-Agent, Routing, Handoff, Queue) → `/orchestrate` 스킬 참조.

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI (전 드라이브 즉시 검색)
  - 예: `es "*.py" -path C:\Users\1\Desktop` / `es ext:mp4 -sort size-descending -n 10`
  - Everything이 실행 중일 때만 작동 (시작프로그램 등록됨)

---

## gstack

웹 브라우징은 `/browse` 스킬 사용. `mcp__claude-in-chrome__*` 도구 사용 금지.

사용 가능한 스킬: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /retro, /investigate, /document-release, /codex, /cso, /autoplan, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade

스킬이 동작하지 않으면: `cd ~/.claude/skills/gstack && ./setup`

---

## Knowledge Vault

- **Location**: `luma3@m4:~/vault/` (MCP: `obsidian-vault`)
- **진입점**: `00-System/VAULT_INDEX.md` → 도메인 `00-INDEX.md` → 파일
- **Write rules**: 리서치 → `10-knowledge/{domain}/`, 프로젝트 → `30-projects/`, 로그 → `40-log/`, 전문가 → `20-experts/`
- **컨벤션**: `_sources/`=법령원문, `_toc.md`=목차매핑, 요약 파일 우선 참조
- **상세**: vault `00-System/SYSTEM_MAP.md` 참조
