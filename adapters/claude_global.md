# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## Self-Execution Guard

작업 시작 전 아래 규칙을 적용한다:

| Condition | Action |
|---|---|
| 코드 작성/수정 50줄+ 또는 4파일+ | Codex 위임 (write 모드) |
| 코드 분석/조사/리뷰 (수정 없음) | Codex 위임 (read-only 모드) |
| 복잡 리서치 (4+ 소스, 트렌드, 50p+ doc) | Gemini 위임 |
| Browser/GUI/canvas/JS SPA (빠른 조회) | `/browse` 스킬 |
| Telegram 발송·수신 / JS 렌더링 + M4 실행 | OpenClaw 위임 |
| 단순 리서치 (≤3 검색, 단일 주제) | Claude 직접 WebSearch/WebFetch |
| 단순 편집 (1-3파일, <50줄) | 직접 수행 |

### Codex 위임

**호출**: `Skill("codex:rescue", args="...")` — `codex exec` 직접 호출 금지.

**플래그**:
- 코드 작성/수정: `--background --write "task"`
- 코드 분석/조사: `--background "task"`
- Follow-up: 위 플래그에 `--resume` 추가
- 단순/포맷팅: `--background --write --model spark --effort low "task"`

**작업 설명 규칙**:
- 절대 경로 명시. Codex의 cwd 추측에 의존 금지.
- 경로 제약: Codex는 현재 cwd 내부만 수정 가능. 외부면 사용자에게 알림.
- 복잡한 작업: `Context Budget - MUST: [필수 파일] / DO NOT: [제외 파일]`, `Done: [검증 커맨드]`

**검증** (코드 작성/수정 한정):
- `git diff --stat` → 100줄 미만: `git diff` 전체 / 100~500줄: 핵심 hunk / 500줄+: 사용자에게 알림
- 이상 발견 시 즉시 알림 (자동 수정 금지)

### Gemini 위임

**호출**: `Skill("gemini:rescue", args="--background ...")` — `gemini -p` 직접 호출 금지.

**플래그**:
- 기본: `--background "task"`
- 심층/대용량: `--background --model pro "task"`

**Timeout & Fallback**: 3분 무응답 → 1회 재시도 → Codex read-only 재위임 (웹 검색 불가 범위만).

### Memory (에이전트 공유 메모리)

`memory-mcp` 도구군 (`mcp__memory-mcp__*`).

- **Gemini 위임 전**: `memory_recall(query, type="research")` 캐시 확인 → 히트 시 Gemini 생략
- **결과 수신 후**: Gemini가 저장 안 한 경우 Claude가 `memory_store` 호출. tags에 한국어+영어 병행.

### OpenClaw 위임

Telegram 발송·수신, JS 렌더링 크롤링, M4 환경 실행 전담. `/browse`(빠른 단일 조회)와 구분.

**SSH 호출**:
```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main --message "작업 지시" \
   --deliver --reply-channel telegram --reply-to <chat_id> \
   --reply-account content-bot'
```

**cron 관리**: `/openclaw` 스킬 | **MCP 직접 발송**: `mcp__openclaw-mcp__messages_send`

---

### 금지 사항

- `Agent(subagent_type=codex-coder|gemini-researcher)` 직접 사용 금지
- vault 저장: 사용자 명시 요청 시만 `mcp__obsidian-vault__write_note`

### Examples

- 새 기능 구현 → `Skill("codex:rescue", args="--background --write \"경로 + 작업\"")`
- 단순 포맷 → `Skill("codex:rescue", args="--background --write --model spark --effort low \"...\"")`
- 파일 분석 → `Skill("codex:rescue", args="--background \"경로 분석: ...\"")`
- AI 트렌드 리서치 → `Skill("gemini:rescue", args="--background \"...\"")`
- 논문 100p → `Skill("gemini:rescue", args="--background --model pro \"...\"")`
- 빗썸 시세 → `/browse` 스킬

---

## 스킬 인프라

- **원본**: `~/projects/custom-skills/` — 모든 편집·생성은 여기서만. `/skill-creator`로 드래프트.
- **배포**: `bash ~/projects/custom-skills/setup.sh` → `~/.claude/skills/` (덮어씀)
- **반영**: `git add && commit && push` → 다른 기기에서 `git pull && bash setup.sh`
- **토글**: `/skill-toggle` — `~/.claude/skills-disabled/`로 이동. version control 대상 아님.

---

## 새 프로젝트 관례

- **위치**: `~/projects/{이름}/` — 명시 없으면 항상 여기
- **초기화**: `/prd {이름}` 스킬

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI. 예: `es "*.py"` / `es ext:mp4 -sort size-descending`

---

## gstack

웹 브라우징은 `/browse` 스킬. `mcp__claude-in-chrome__*` 도구 사용 금지.
동작 안 하면: `cd ~/.claude/skills/gstack && ./setup`

---

## Knowledge Vault

- **위치**: `m4:~/vault/` (MCP: `obsidian-vault`). 작업 전 `00-System/VAULT_INDEX.md` 읽을 것.
- **쓰기**: MCP 또는 M4 직접. 로컬 clone 금지.
- **경로**: 리서치→`10-knowledge/` / 전문가→`20-experts/` / 프로젝트→`30-projects/` / 임시→`00-inbox/` / 로그→`40-log/YYYY-MM-DD.md`
- **Frontmatter 필수**: type, domain, source, date, status
