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

### 스킬 파이프라인 맵 (진입점 중심)

여러 스킬이 이어지는 파이프라인. **진입점만 기억**하면 됨 — 중간 단계는 진입점이 다음 단계를 제안하거나 이어받는다. 중간 단계 스킬을 단독으로 부를 수도 있지만(이미 산출물 있을 때) 기본은 진입점.

- **디자인 (gstack)**: `/design-consultation` → `/design-shotgun` → `/design-html` → `/design-review`
  - 시스템 없으면 `/design-consultation`부터, 이미 DESIGN.md 있으면 `/design-shotgun`부터, 라이브 사이트 QA는 `/design-review` 직행
- **플랜 리뷰 (gstack)**: `/autoplan` = `/plan-ceo-review` + `/plan-eng-review` + `/plan-design-review` + `/plan-devex-review` 묶음 실행. 개별 리뷰 원하면 각 스킬 직접.
- **배포 (gstack)**: `/qa` → `/ship` → `/land-and-deploy` → `/canary`. 리포트만 원하면 `/qa-only`, 배포 설정은 `/setup-deploy`.
- **보안 (gstack)**: `/cso` (전체) / `/cso --skills` / `/cso --infra` / `/cso --comprehensive`. 리뷰 전용은 `/review`, `/security-review`.
- **브라우저 (gstack)**: `/browse`(headless) ↔ `/connect-chrome`(headed + Side Panel). 쿠키 필요하면 `/setup-browser-cookies`.
- **조사/기획 (내 커스텀)**: `/prd {이름}` (프로젝트 초기화) / `/research` (논문) / `/office-hours` (아이디어 브레인스토밍) / `/investigate` (버그 루트코즈).
- **크리에이티브 (내 커스텀)**: `/drawing`(이미지) / `/color`(팔레트) / `/writing`(글쓰기·블로그 발행) / `/video`(유튜브 파이프라인) / `/music`(ACE-Step) / `/transcribe`(Whisper).
- **브리핑/회고 (내 커스텀)**: `/events` / `/github-trends` / `/it-contents` / `/weekly-review` / `/retro` / `/session-end` / `/growth-review`(월간 자기평가).
- **외부 시스템 (내 커스텀)**: `/channel`(텔레그램) / `/openclaw`(M4 cron) / `/ingredient`(식재료) / `/investment`(투자봇) / `/map`(시스템 지도).

진입점 스킬이 파이프라인 다음 단계를 자동으로 호출하진 않는다 — **제안만** 하고 사용자가 다음 진입을 결정.

---

## 프로젝트 관례

- **위치**: `~/projects/{이름}/` — 명시 없으면 항상 여기
- **분류 메모**: `~/projects/INDEX.md` — Active/Maintained/Archive 분류 + 한 줄 설명. 새 프로젝트 만들면 Active에 추가, 1주+ 미수정 시 Maintained 검토. 폴더 이동 X (절대경로 의존성 보존)
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
  - `Error 8: Everything IPC not found` 시 본체가 user 세션에 안 떠 있는 것: `cmd //c start "" "C:\Program Files\Everything\Everything.exe" -startup`

---

## Google Workspace 로컬 도구

- **`gws`** — 비공식 Google Workspace CLI (`~/AppData/Roaming/npm/gws`, 2026-03 출시, OAuth 완료)
- **Gmail/Drive/Calendar 조회는 `mcp__claude_ai_*` connector보다 `gws` 우선** — 스크립트화·필터링·MCP 토큰 절약
- 패턴: `gws <service> <resource> [sub] <method> --params '<JSON>' [--format json|table|yaml|csv]`
- 서비스: drive · gmail · calendar · sheets · docs · tasks · slides · people · keep · meet · classroom · forms · chat · script · admin-reports · workflow
- 예: `gws gmail users messages list --params '{"userId":"me","maxResults":3}' --format table`
- 스키마 조회: `gws schema gmail.users.messages.list` · 페이지네이션: `--page-all` (NDJSON)

---

## 로컬 데이터 자료실

- **위치**: `D:\datasets\` — 한국어/한국 데이터셋 모음 (총 ~6.3 GB)
- **인덱스**: `D:\datasets\INDEX.md` — 메인 페르소나(Nemotron-Personas-Korea 100만), KMMLU·KLUE·CLIcK 평가, lbox-open 판례, KOSIS API 추출 CSV 등 전체 카탈로그·로드 코드·라이선스
- **세션 시작 규칙**: 데이터 분석·페르소나 시뮬·통계 비교 작업 요청 시 먼저 `INDEX.md` 1회 읽고 진행
- **API 키**: `KOSIS_API_KEY`는 `D:\datasets\.env`, `DART_API_KEY`는 Windows User env (`os.environ['DART_API_KEY']`)에서 직접 로드

---

## 외부 도구 역할 분리

### Obsidian Vault — 개인 지식 저장소 (나만 봄)
- **위치**: `m4:~/vault/` (MCP: `obsidian-vault`). PARA × Johnny Decimal 구조, 깊이 ≤5단계
- **용도**: 리서치 원본, 세션 로그, 아이디어 메모, 학습 노트
- **경로**: 임시→`05-Inbox/` / 도메인 지식→`10-Resources/10.0X-{Cat}/` / 전문가→`20-Areas/` / 프로젝트→`30-Projects/` / 로그→`40-Logs/YYYY-MM-DD.md` / 종료→`90-Archives/`. 카테고리 매핑은 vault `00-System/VAULT_INDEX.md` (JDex)
- **쓰기**: MCP 또는 M4 직접. 로컬 clone 금지. **Area·Category 폴더에 파일 직접 저장 금지** (ID 폴더 안에만). Frontmatter 필수 (type, domain, source, date, status)
- **검증 우선**: vault 경로를 코드 변수·옛 로그에서 가져오지 말 것 — 옛 폴더(예: 사라진 `10-knowledge/`)가 박혀 있을 수 있다. 새 vault 작업 전 `ssh m4 'ls <경로>'`로 존재 검증 + 카테고리 매핑은 항상 `~/vault/00-System/VAULT_INDEX.md`(JDex)에서 확인

### Notion — 외부 공유용 대시보드 (남에게 보여줌)
- **용도**: 포트폴리오, 프로젝트 소개, 정리된 문서, 팀/외부 공유 자료
- **MCP**: `notion-ext-mcp` (연결됨). 도구: `mcp__notion-ext-mcp__notion_*`
- **원칙**: publish-ready 콘텐츠만. 작업 중인 초안은 프로젝트 폴더 또는 vault에
