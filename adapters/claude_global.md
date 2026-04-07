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
| 코드 작성/수정 50줄+ 또는 4파일+ | Codex 위임 (write 모드) |
| 코드 분석/조사/리뷰 (수정 없음) | Codex 위임 (read-only 모드) |
| 복잡 리서치 (4+ 소스, 트렌드, 50p+ doc) | Gemini 위임 |
| Browser/GUI/canvas/JS SPA | `/browse` 스킬 |
| 단순 리서치 (≤3 검색, 단일 주제) | Claude 직접 WebSearch/WebFetch |
| 단순 편집 (1-3파일, <50줄) | 직접 수행 |

### Codex 위임

**호출 방법**: `Skill` 도구로 `codex:rescue` 호출. `codex exec` 직접 호출 금지.

**플래그 조합**:
- 코드 작성/수정: `--background --write "task"`
- 코드 분석/조사: `--background "task"` (write 없음)
- Follow-up (사용자가 "이어서/계속/그 작업" 등 언급): 위 플래그에 `--resume` 추가
- 새 작업이지만 이전 thread와 무관: `--fresh` 추가

**모델/Effort**:
- 단순 (단일 함수, 보일러플레이트, 포맷팅, 단순 변환): `--model spark --effort low`
- 그 외 (새 기능, 리팩토링, 디버깅, 멀티파일): 플래그 생략 → codex config 기본 (gpt-5.4/high)

**작업 설명 규칙**:
- 항상 절대 경로 포함 (예: `~/Projects/agent-orchestration/scripts/foo.sh`)
- 변경 대상 파일을 명시 (Codex의 cwd 추측에 의존하지 말 것)
- **경로 제약**: Codex는 workspace-write sandbox → 현재 cwd 내부 경로만 수정 가능. 외부 경로 요청 시 사용자에게 "workspace 외부입니다. cwd 이동 또는 직접 수행 필요" 알림.

**위임 시작 패턴**:
1. 사용자에게 명시: "Codex 위임 시작 (모델/effort) — 작업: [한 줄 요약], 대상: [파일/영역]"
2. `TaskCreate`로 task list에 등록 (제목: "Codex: [작업명]")
3. background 알림 대기

**완료 알림 수신 시**:
1. 보고: "Codex 완료 (모델/effort/소요시간) — [결과 요약]"
2. 모델/effort 표기: spark/low 또는 gpt-5.4/high (플래그 생략 시)
3. `TaskUpdate`로 완료 처리
4. 코드 작업이면 검증 단계 수행

**검증** (코드 작성/수정 작업 한정):
- `git diff --stat` 먼저 실행 → 변경 규모 파악
- 변경 100줄 미만: `git diff` 전체 읽고 핵심 확인
- 100~500줄: 파일별 핵심 hunk만 확인
- 500줄+: 변경 파일 목록 + 사용자에게 "diff가 큽니다, 검증 원하시면 알려주세요"
- 이상 발견 시 사용자에게 즉시 알림 (자동 수정 금지)

### Gemini 위임

`Bash("gemini -p \"task\"")` 직접 호출. 결과 수신 후 검증:
- 결과가 비어있거나 200자 미만: "Gemini 응답 비정상 — 재시도 필요" 알림
- 결과가 있으면 핵심 요약 보고

### 금지 사항

- `Agent(subagent_type=codex-coder|gemini-researcher)` 직접 사용 금지 (단, plugin 내장 subagent는 Skill 도구를 통한 호출 허용)
- vault 저장: 사용자 명시 요청 시만 `mcp__obsidian-vault__write_note`

### Examples

- "지뢰찾기 게임 만들어줘" (Python ~100줄)
  → `Skill("codex:rescue", args="--background --write \"~/projects/minesweeper/ 에 Python CLI 지뢰찾기 게임 구현\"")`
- "이 함수 리팩토링해줘" (5+파일)
  → `Skill("codex:rescue", args="--background --write \"~/Projects/X/src/foo.py 의 process_data 함수를 ... 로 리팩토링\"")`
- "테스트 보일러플레이트 만들어줘" (단순)
  → `Skill("codex:rescue", args="--background --write --model spark --effort low \"...\"")`
- "이 파일 분석해줘" (read-only)
  → `Skill("codex:rescue", args="--background \"~/Projects/X/src/foo.py 분석: ...\"")`
- "그 작업 이어서" (follow-up)
  → 직전 위임 + `--resume`
- "README 첫 줄 수정" → 직접 수행
- "AI 프레임워크 5개 비교" → `Bash("gemini -p \"...\"")`
- "빗썸 시세" → `/browse` 스킬

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

- **커맨드 원본**: `~/projects/custom-skills/{스킬명}/SKILL.md`
- **적용 방식**: `~/.claude/commands/`에 심볼릭 링크로 연결
- **대상 기기**: Mac Air (luma2), M4 (luma3), Windows (1)

커맨드 추가/수정 시:
```bash
# custom-skills repo에서 편집 후 push
cd ~/projects/custom-skills && git add -A && git commit -m "feat: ..." && git push

# 다른 기기에서 동기화
cd ~/projects/custom-skills && git pull && bash setup.sh
```

직접 `~/.claude/commands/`에 파일을 만들지 말 것 — repo에 반영되지 않음.
