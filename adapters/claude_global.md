# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## 기본 규칙

- 한국어로 소통
- 간결하게 응답

## 모델 라우팅 규칙

| 모델 | 용도 | 금지 |
|---|---|---|
| **Sonnet** | 판단·위임·단순 편집 (1-3파일, <50줄) | 버그 수정, 기능 구현 |
| **Opus** | 아키텍처·전략 (월 5-10회) | 코드 생성, 일상 판단 |
| **Codex** | 4+파일/50+줄 구현, 리팩토링, 코드 리뷰 | — |
| **Gemini** | 웹 리서치, 50p+ 문서, 배치 크롤링 | — |

모델이 부적절하면 세션 시작 시 한 번만: "이 작업은 [모델]이 적합해요."

---


## Self-Execution Guard

작업 시작 전 아래 규칙을 적용한다:

| Condition | Action |
|---|---|
| 50+ lines of code to write | `Bash("codex exec --full-auto --skip-git-repo-check \"task\"")` |
| 4+ files to create/modify | `Bash("codex exec --full-auto --skip-git-repo-check \"task\"")` |
| Complex research (4+ sources, trend, crawl, 50p+ doc) | `Bash("gemini -p \"task\"")` |
| Browser/GUI/canvas/JS SPA needed | `/browse` 스킬 사용 |
| Simple research (≤3 searches, single topic) | Claude 직접 WebSearch/WebFetch |
| Simple edit (1-4 files, <50 lines) | 직접 수행 |

**위임 방법**: `Bash` 도구로 CLI 직접 호출. `Agent(subagent_type=...)` 사용 금지.
**vault 저장**: 리서치 후 사용자가 명시적으로 요청할 때만 `mcp__obsidian-vault__write_note` 호출.

Examples:
- "지뢰찾기 게임 만들어줘" → Python ~100줄 → `codex exec --full-auto --skip-git-repo-check "task"`로 위임
- "README 첫 줄 수정" → 1파일 1줄 → 직접 수행
- "이 라이브러리 최신 버전 찾아줘" → 단순 검색 → Claude 직접 처리
- "AI 에이전트 프레임워크 5개 비교해줘" → 복잡 리서치 → `gemini -p "task"`로 위임
- "빗썸 시세 긁어줘" / "차트 만들어줘" / "네이버 검색해줘" → `/browse` 스킬

---

## 스킬 제작 관례

- **새 스킬 만들 때**: 반드시 `/skill-creator` 스킬을 통해 드래프트 → 테스트 → 평가 → 개선 과정을 거친다
- **기존 스킬 개선 시**: `/skill-creator`로 eval 돌려 검증 후 반영
- 단순 설정 파일(SKILL.md) 직접 편집은 긴급 패치에만 허용, 이후 `/skill-creator` 로 재검증 필요

---

## 새 프로젝트 관례

- **위치**: 모든 새 프로젝트는 `C:\Users\1\projects\{이름}\` (bash: `~/projects/{name}/`) 에 생성
- **초기화**: `/prd {이름}` 스킬로 폴더 생성 + CLAUDE.md 자동 작성 + VS Code 오픈
- 명시적 위치 지정 없으면 항상 이 경로 사용

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI (전 드라이브 즉시 검색)
  - 예: `es "*.py" -path C:\Users\1\Desktop` / `es ext:mp4 -sort size-descending -n 10`
  - Everything이 실행 중일 때만 작동 (시작프로그램 등록됨)

---

## gstack

웹 브라우징은 `/browse` 스킬 사용. `mcp__claude-in-chrome__*` 도구 사용 금지.
스킬이 동작하지 않으면: `cd ~/.claude/skills/gstack && ./setup`

---


## Knowledge Vault

- **Location**: `luma3@m4:~/vault/` (MCP: `obsidian-vault`)
- **Entry point**: `00-System/VAULT_INDEX.md` — 에이전트가 vault 작업 전 반드시 읽을 것
- **쓰기 권한**: **MCP `obsidian-vault` 또는 M4 직접** — 다른 기기에서 쓸 때는 MCP 사용
  - 로컬 vault clone 금지 (혼동 방지 — Windows vault는 삭제됨)
- **Write rules**: 리서치→`10-knowledge/`, 전문가→`20-experts/`, 프로젝트→`30-projects/`, 임시→`00-inbox/`, 로그→`40-log/YYYY-MM-DD.md`
- **Frontmatter 필수**: type, domain, source, date, status

---

## Claude Code 커맨드 관리

- **커맨드 원본**: `~/projects/claude-code-setup/claude/commands/`
- **적용 방식**: `~/.claude/commands/`에 심볼릭 링크로 연결
- **대상 기기**: Mac Air (luma2), M4 (luma3), Windows (1)

커맨드 추가/수정 시:
```bash
# repo에서 편집 후 push
cd ~/projects/claude-code-setup && git add -A && git commit -m "feat: ..." && git push

# 다른 기기에서 동기화
cd ~/projects/claude-code-setup && git pull && bash install.sh
```

직접 `~/.claude/commands/`에 파일을 만들지 말 것 — repo에 반영되지 않음.
