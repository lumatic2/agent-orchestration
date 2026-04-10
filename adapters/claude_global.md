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
- 단순 (단일 함수, 보일러플레이트, 포맷팅, 단순 변환): `--model spark --effort medium`
- 그 외 (새 기능, 리팩토링, 디버깅, 멀티파일): 플래그 생략 → codex config 기본 (gpt-5.4/medium)

**작업 설명 규칙**:
- 항상 절대 경로 포함 (예: `~/Projects/agent-orchestration/scripts/foo.sh`)
- 변경 대상 파일을 명시 (Codex의 cwd 추측에 의존하지 말 것)
- **경로 제약**: Codex는 workspace-write sandbox → 현재 cwd 내부 경로만 수정 가능. 외부 경로 요청 시 사용자에게 "workspace 외부입니다. cwd 이동 또는 직접 수행 필요" 알림.
- **복잡한 작업 시** task 문자열에 추가: `Context Budget - MUST: [필수 파일] / DO NOT: [제외 파일]`, `Done: [검증 커맨드]`

**위임 시작 패턴**:
1. 사용자에게 명시: "Codex 위임 시작 (모델/effort) — 작업: [한 줄 요약], 대상: [파일/영역]"
2. `TaskCreate`로 task list에 등록 (제목: "Codex: [작업명]")
3. background 알림 대기

**완료 알림 수신 시**:
1. 보고: "Codex 완료 (모델/effort/소요시간) — [결과 요약]"
2. 모델/effort 표기: spark/low 또는 gpt-5.4/medium (플래그 생략 시)
3. `TaskUpdate`로 완료 처리
4. 코드 작업이면 검증 단계 수행

**검증** (코드 작성/수정 작업 한정):
- `git diff --stat` 먼저 실행 → 변경 규모 파악
- 변경 100줄 미만: `git diff` 전체 읽고 핵심 확인
- 100~500줄: 파일별 핵심 hunk만 확인
- 500줄+: 변경 파일 목록 + 사용자에게 "diff가 큽니다, 검증 원하시면 알려주세요"
- 이상 발견 시 사용자에게 즉시 알림 (자동 수정 금지)

### Gemini 위임

**호출 방법**: `Skill("gemini:rescue", args="--background ...")`. `gemini -p` 직접 호출 금지.

**플래그 조합**:
- 기본: `--background "task내용"`
- 심층 분석/대용량 문서: `--background --model pro "task내용"`

**모델 라우팅**:
- 단순 질문/빠른 요약/최신 정보 확인: 플래그 생략 → flash (gemini-3-flash-preview)
- 기술 문서 분석/논문/장문 처리/여러 소스 종합/트렌드 비교 (3개+ 대상): `--model pro` (gemini-3.1-pro-preview)

**보고**: Codex와 동일 패턴. "Gemini 위임 시작/완료 (모델/소요시간)". 결과 300자 미만이면 "응답 비정상 — 재시도 필요" 알림.

### 금지 사항

- `Agent(subagent_type=codex-coder|gemini-researcher)` 직접 사용 금지 (단, plugin 내장 subagent는 Skill 도구를 통한 호출 허용)
- vault 저장: 사용자 명시 요청 시만 `mcp__obsidian-vault__write_note`

### Examples

- 새 기능 구현 (~100줄) → `Skill("codex:rescue", args="--background --write \"경로 + 작업\"")`
- 단순 변환/포맷 → `Skill("codex:rescue", args="--background --write --model spark --effort low \"...\"")`
- 파일 분석 (read-only) → `Skill("codex:rescue", args="--background \"경로 분석: ...\"")`
- 이어서 → 위 플래그에 `--resume` 추가
- AI 트렌드 리서치 → `Skill("gemini:rescue", args="--background \"...\"")`
- 논문 100p 분석 → `Skill("gemini:rescue", args="--background --model pro \"...\"")`
- 빗썸 시세 → `/browse` 스킬

---

## 스킬 제작 관례

**canonical 위치**: `~/projects/custom-skills/{이름}/` — 모든 스킬 편집·생성·삭제는 여기서만. `~/.claude/skills/`는 배포 사본(git 레포 아님)이고 `setup.sh`가 덮어쓴다.

**새 스킬 만들 때**:
1. `/skill-creator` 스킬로 드래프트 → 테스트 → 평가 → 개선 과정을 거친다
2. **드래프트 저장 경로는 항상 `~/projects/custom-skills/{이름}/`** (`~/.claude/skills/` 아님!)
3. 배포: `bash ~/projects/custom-skills/setup.sh`
4. 커밋·푸시: canonical repo에서 `git add {이름} && git commit && git push`
5. 다른 기기 반영: 각 기기에서 `git pull && bash setup.sh`

**기존 스킬 개선 시**: 위 1~5 동일 (canonical에서 편집).

**예외**: 긴급 패치는 `~/.claude/skills/`에서 직접 편집 허용. 단 즉시 canonical에도 반영 필요 (다음 `setup.sh` 실행 시 덮어써짐).

**토글 (켜고 끄기)**: `/skill-toggle` — `~/.claude/skills/`와 `~/.claude/skills-disabled/` 사이로 디렉토리 이동. 기기별 상태, version control 대상 아님.

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

- **Location**: `m4:~/vault/` (MCP: `obsidian-vault`)
- **Entry point**: `00-System/VAULT_INDEX.md` — 에이전트가 vault 작업 전 반드시 읽을 것
- **쓰기 권한**: **MCP `obsidian-vault` 또는 M4 직접** — 다른 기기에서 쓸 때는 MCP 사용
  - 로컬 vault clone 금지 (혼동 방지 — Windows vault는 삭제됨)
- **Write rules**: 리서치→`10-knowledge/`, 전문가→`20-experts/`, 프로젝트→`30-projects/`, 임시→`00-inbox/`, 로그→`40-log/YYYY-MM-DD.md`
- **Frontmatter 필수**: type, domain, source, date, status

---

## 스킬 인프라 (custom-skills repo)

- **Canonical 원본**: `~/projects/custom-skills/` (lumatic2/custom-skills git repo) — 유일한 편집 위치
- **배포 타겟**: `~/.claude/skills/` — `setup.sh`가 덮어씀. git repo 아님. 직접 편집은 긴급 패치만.
- **토글 보관소**: `~/.claude/skills-disabled/` — 기기별 OFF 스킬 저장소. version control 대상 아님.
- **대상 기기**: Mac Air, M4 Mac, Windows

**동기화 워크플로**:
1. `~/projects/custom-skills/`에서 편집/생성
2. `bash ~/projects/custom-skills/setup.sh` → `~/.claude/skills/`로 배포 (skills-disabled는 skip)
3. `git add && commit && push`
4. 다른 기기에서 `git pull && bash setup.sh`

**setup.sh 안전 보장**:
- canonical에 없는 디렉토리는 건드리지 않음 (orphan 경고만 출력)
- `~/.claude/skills-disabled/`에 있는 이름은 skip (토글 상태 유지)
- 플랫 `*-public.md`, `README.md`, `CLAUDE.md`는 배포 제외

**직접 `~/.claude/skills/`에 파일을 만들지 말 것** — canonical에 반영 안 되고, 다른 기기로 전파 안 됨.
