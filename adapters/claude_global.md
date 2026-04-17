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

### Memory — 두 시스템

- **Auto memory** (파일, 프로젝트별, 자동 로드): 선호·피드백·프로젝트 맥락. "기억해둬" 기본 처리 대상
- **Vault** (M4 Obsidian, 전역): 여러 프로젝트에서 재사용할 지식·리서치·레시피. 아래 "외부 도구 역할 분리" 참조

### OpenClaw 위임

Telegram·JS 렌더링 크롤링·M4 실행은 `/openclaw` 스킬 경유.

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

## 외부 도구 역할 분리

### Obsidian Vault — 개인 지식 저장소 (나만 봄)
- **위치**: `m4:~/vault/` (MCP: `obsidian-vault`)
- **용도**: 리서치 원본, 세션 로그, 아이디어 메모, 학습 노트
- **경로**: 리서치→`10-knowledge/` / 전문가→`20-experts/` / 프로젝트→`30-projects/` / 임시→`00-inbox/` / 로그→`40-log/YYYY-MM-DD.md`
- **쓰기**: MCP 또는 M4 직접. 로컬 clone 금지. Frontmatter 필수 (type, domain, source, date, status)

### Notion — 외부 공유용 대시보드 (남에게 보여줌)
- **용도**: 포트폴리오, 프로젝트 소개, 정리된 문서, 팀/외부 공유 자료
- **MCP**: `notion-ext-mcp` (연결됨). 도구: `mcp__notion-ext-mcp__notion_*`
- **원칙**: publish-ready 콘텐츠만. 작업 중인 초안은 프로젝트 폴더 또는 vault에
