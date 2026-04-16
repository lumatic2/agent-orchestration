# Claude Code — Global Instructions
<!-- ⚠️ 원본 파일: adapters/claude_global.md (agent-orchestration 레포)
     ~/CLAUDE.md 는 sync.sh가 여기서 복사한 배포본 — 직접 편집 금지 -->

## 오케스트레이션 원칙: Verification-First

Claude(나)가 **주 실행자**다. 코드 편집·WebSearch·파일 분석·계획 수립은 직접 수행.
**위임은 노동 offloading이 아니라 교차검증 목적**으로만 사용한다:
- 독립 모델의 관점으로 할루시네이션 감소
- 설계/가정 도전 (adversarial review)
- Google 인덱스 기반 사실 검증 (Gemini)

**자동 트리거 금지**. 위임 필요 판단 시 사용자에게 **제안만** 하고 승인 대기. 모든 위임은 **background + 실패 허용**.

### 진입점: `/codex`, `/gemini` 스킬

모든 Codex/Gemini 호출은 스킬 경유. 스킬이 맥락 수집 → 추천 → 실행을 담당한다.

- **Codex** (`/codex`): 코드 리뷰, adversarial review(설계/가정 도전), rescue(조사·진단·구현 위임)
- **Gemini** (`/gemini`): 최신성 fact-check, 대용량 문서 요약(2M+), research, rescue

호출 타이밍은 사용자 판단. Claude는 호출 안 하고 답만 낸다. 단:
- 고위험 맥락(migration/auth/crypto/security 파일 변경): 답 끝에 "`/codex` 교차검증 가능" 한 줄.
- **Codex rescue/task 결과 보고 후** 후속 작업 가능성이 있으면: "이어서 작업은 `/codex resume <지시>`로 thread 유지 가능" 한 줄.

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
- **worktree 라이프사이클**: 임시 작업 공간으로 사용. 작업 완료 후 사용자가 "합치고 정리해줘"라고 하면:
  1. main worktree에서 `git merge {브랜치명}`
  2. `git worktree remove .claude/worktrees/{이름}`
  3. `git branch -d {브랜치명}`
  - 충돌 시 사용자에게 보고 후 해결. 병렬 워크트리는 서로 다른 파일을 수정하도록 권장

---

## 사용자 컨텍스트

- **기본 위치**: 서울특별시 종로구 명륜3길 27 (명륜동, 성균관대 인근). 좌표 ≈ lat 37.585 / lng 126.999
  - 위치 기반 질의("내 주변", "가까운 ○○")의 기준점. 다이소·편의점·영화관 MCP 탐색 시 이 주소 사용

---

## Windows 로컬 도구

- **파일 검색**: `es "검색어"` — Everything CLI. 예: `es "*.py"` / `es ext:mp4 -sort size-descending`

---

## NPM CLI 도구

### ast-grep (sg) — 구조적 코드 검색/치환
AST 기반 매칭. Grep이 텍스트라면 `sg`는 코드 구조. 문자열·주석의 오탐을 배제.
- **쓸 때**: 리팩토링, codemod, "특정 함수 호출만 골라내기", AST 패턴 탐색
- **안 쓸 때**: 단순 문자열/주석 검색 — Grep이 빠름
- **예시**:
  ```bash
  sg --pattern 'print($A)' --lang python scripts/            # print() 호출만
  sg --pattern 'console.log($A)' --rewrite 'logger.debug($A)' -l js -U  # 일괄 치환
  ```

### mmdc (@mermaid-js/mermaid-cli) — 다이어그램 렌더
mermaid 텍스트를 PNG/SVG로 변환. 아키텍처·플로우·시스템 구조 설명 시 선제적 사용.
- `mmdc -i diagram.mmd -o diagram.png`
- 복잡한 관계 설명은 텍스트 나열보다 다이어그램이 직관적일 때 이미지로 제시

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
