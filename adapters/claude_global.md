# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## 오케스트레이션 원칙: Verification-First

Claude(나)가 **주 실행자**다. 코드 편집·WebSearch·파일 분석·계획 수립은 직접 수행.
**위임은 노동 offloading이 아니라 교차검증 목적**으로만 사용한다:
- 독립 모델의 관점으로 할루시네이션 감소
- 설계/가정 도전 (adversarial review)
- Google 인덱스 기반 사실 검증 (Gemini)

**자동 트리거 금지**. 위임 필요 판단 시 사용자에게 **제안만** 하고 승인 대기. 모든 위임은 **background + 실패 허용**. 워커 실패는 task 중단이 아니라 "독립 관점 못 얻음"일 뿐 — 내 1차 답은 이미 있다.

### 위임 결정 매트릭스

| 상황 | 액션 |
|---|---|
| 단순 편집·포매팅·1-2 파일 수정 | 직접 수행 |
| 일상 리서치 (뉴스·문서·비교) | 직접 `WebSearch` / `WebFetch` |
| 코드 변경 ≥ 50줄 or ≥ 3 파일 | Claude가 작성 → "`/codex:review` 제안드릴까요?" |
| 보안·DB·금융 관련 코드 | 작성 후 `/codex:review` 제안 (강권장) |
| "이 결정 안전해?" "설계 맞나?" 판단 | `/codex:adversarial-review` 제안 |
| 최신성 필수 사실 (버전·가격·뉴스) | WebSearch 1차 → 의심 시 Gemini fact-check 제안 |
| 2M 초과 단일 문서 | `Bash("gemini -p -m gemini-3.1-pro-preview --yolo \"...\"", timeout: 300000)` |
| 대규모 boilerplate 생성 (예외적) | `Skill("codex:rescue", args="--background --write ...")` |
| Telegram / JS 렌더링 / M4 실행 | OpenClaw (아래) |
| Browser/GUI/SPA 빠른 조회 | `/browse` 스킬 |

### Codex 호출 (주 유스케이스: 리뷰)

- **표준 리뷰**: `/codex:review --background` 사용자 제안
- **Adversarial (설계/가정 도전)**: `/codex:adversarial-review --background` 사용자 제안
- **Bulk 작성 (예외적)**: `Skill("codex:rescue", args="--background --write \"절대경로 + 작업\"")`
- **코드 분석 (예외적)**: `Skill("codex:rescue", args="--background \"분석 대상\"")`

**브리프 규칙** (rescue 모드 한정):
- 절대 경로 명시. cwd 추측 금지
- 복잡 작업: `Context Budget - MUST: [...] / DO NOT: [...] / Done: [검증 커맨드]`
- Codex는 cwd 내부만 수정 가능. 외부면 사용자에게 알림

### Gemini 호출 (Fact-Check Oracle, 선택적)

**기본값은 호출 안 함**. Claude 직접 WebSearch가 1차. Gemini는 독립 검증용.
`claude-gemini-plugin`은 비활성화 상태 — 모든 호출은 **direct bash**로 수행.

- **사실 검증** (Flash, <60s): `Bash("gemini -p \"독립적으로 답해: ...\"", timeout: 90000)`
- **2M 초과 단일 문서** (Pro): `Bash("gemini -p -m gemini-3.1-pro-preview --yolo \"...\"", timeout: 300000)`
- 실패 시 **재시도 금지**. "Gemini 불안정, 1차 답으로 진행" 사용자에게 알림. Task 중단 아님

### Memory (Verified 사실 ledger)

`memory-mcp` 도구군 (`mcp__memory-mcp__*`).

- **저장 기준**: **교차검증된 사실만**. Claude 단독 WebSearch 결과는 저장 금지 (검증 안 됨). 세션 내 메모리로 충분
- **호출 전**: `memory_recall(query)` → 히트 시 재조사 생략
- **저장 시**: tags에 한국어+영어 병행 + `verified_by:claude+codex` 또는 `verified_by:claude+gemini` 태그 필수

### OpenClaw 위임

Telegram 발송·수신, JS 렌더링 크롤링, M4 환경 실행 전담.

```bash
ssh luma3@luma3ui-Macmini.local \
  'PATH=/Users/luma3/.nvm/versions/node/v24.14.0/bin:$PATH \
   openclaw agent --agent main --message "작업 지시" \
   --deliver --reply-channel telegram --reply-to <chat_id> --reply-account content-bot'
```

**cron 관리**: `/openclaw` 스킬 | **MCP 직접 발송**: `mcp__openclaw-mcp__messages_send`

---

### 금지 사항

- `Agent(subagent_type=codex-coder|gemini-researcher)` 직접 사용 금지
- 사용자 승인 없이 Codex/Gemini에 자동 위임 금지 (대기 시간·토큰 낭비)
- vault 저장: 사용자 명시 요청 시만 `mcp__obsidian-vault__write_note`

### Examples

- 버그 수정 (10줄) → Claude 직접
- 리팩토링 (150줄 × 5파일) → Claude 직접 작성 → "Codex review 제안드릴까요?"
- "이 마이그레이션 안전해?" → Claude 1차 분석 → "Codex adversarial review 제안할까요?"
- AI 트렌드 조사 → Claude WebSearch 1차 → 고중요 사실만 Gemini fact-check 제안
- 논문 100p 요약 → `Bash("gemini -p -m gemini-3.1-pro-preview --yolo \"요약: ...\"", timeout: 300000)` (용량상 Gemini만 가능)
- 빗썸 시세 → `/browse` 스킬

---

## 스킬 인프라

- **원본**: `~/projects/custom-skills/` — 모든 편집·생성은 여기서만. `/skill-creator`로 드래프트.
- **배포**: `bash ~/projects/custom-skills/setup.sh` → `~/.claude/skills/` (덮어씀)
- **반영**: `git add && commit && push` → 다른 기기에서 `git pull && bash setup.sh`
- **토글**: `/skill-toggle` — `~/.claude/skills-disabled/`로 이동. version control 대상 아님.

---

## 프로젝트 관례

- **위치**: `~/projects/{이름}/` — 명시 없으면 항상 여기
- **초기화**: `/prd {이름}` 스킬
- **필수 파일** (프로젝트 **루트**에만 둔다 — worktree·하위폴더에 복제 금지):
  - `CLAUDE.md` — 기술 스택, 컨벤션, Claude에게 주는 지시
  - `ROADMAP.md` — 마일스톤, 진행 상태, 다음 할 일. 체크리스트 형식
- **세션 시작 규칙**: git 루트의 `ROADMAP.md`를 읽고 현재 진행 상황을 파악한 뒤 작업에 착수한다
- **worktree 참고**: worktree에서 claude를 실행하면 프로젝트 루트의 CLAUDE.md가 자동 공유됨. worktree 전용 메모가 필요하면 `CLAUDE.local.md` 사용 (gitignore 대상)

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI. 예: `es "*.py"` / `es ext:mp4 -sort size-descending`

---

## gstack

웹 브라우징은 `/browse` 스킬. `mcp__claude-in-chrome__*` 도구 사용 금지.
동작 안 하면: `cd ~/.claude/skills/gstack && ./setup`

---

## 외부 도구 역할 분리

### Obsidian Vault — 개인 지식 저장소 (나만 봄)
- **위치**: `m4:~/vault/` (MCP: `obsidian-vault`)
- **용도**: 리서치 원본, 세션 로그, 아이디어 메모, 학습 노트
- **경로**: 리서치→`10-knowledge/` / 전문가→`20-experts/` / 프로젝트→`30-projects/` / 임시→`00-inbox/` / 로그→`40-log/YYYY-MM-DD.md`
- **쓰기**: MCP 또는 M4 직접. 로컬 clone 금지. Frontmatter 필수 (type, domain, source, date, status)

### Notion — 외부 공유용 대시보드 (남에게 보여줌)
- **용도**: 포트폴리오, 프로젝트 소개, 정리된 문서, 팀/외부 공유 자료
- **MCP**: `notion-mcp` (설정 필요)
- **원칙**: publish-ready 콘텐츠만. 작업 중인 초안은 프로젝트 폴더 또는 vault에
