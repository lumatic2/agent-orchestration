# agent-orchestration ROADMAP

> 마지막 업데이트: 2026-04-26

## proj 런처 공개 준비

### 독립 레포 분리
- [x] `proj` 관련 코드만 추출 (proj.zsh, powershell_profile.ps1의 proj 함수)
- [x] 원클릭 설치 스크립트 작성 (setup.sh / setup.ps1)
- [x] README 작성: 기능 설명, 스크린샷/GIF, 설치 방법
- [x] GitHub 레포 생성 및 푸시

### 블로그 글
- [ ] "비개발자가 Claude Code로 20개 프로젝트를 관리하며 만든 런처" 초안
- [ ] 스크린샷 캡처 (proj 메뉴, status, archive, agent 선택 등)
- [ ] 브런치 또는 포트폴리오 블로그에 발행
- [ ] GitHub 레포 링크 연결

## proj 기능 개선
- [x] Windows(PowerShell) / Mac(zsh) 코드 통일
- [x] fzf 기반 메뉴 + 단축키 (ctrl+N/E/R/D)
- [x] 관리 액션 후 메뉴 복귀 (while 루프)
- [x] pin/archive 필드 (ctrl+P, ctrl+X, ctrl+A)
- [x] Esc 단계별 뒤로가기 (agent→worktree→project)
- [x] ctrl+S status 화면 (git/branch/worktree/ROADMAP)
- [x] Windows Terminal proj 프로필 추가
- [x] fzf 후 claude stdin 격리 (Start-Process)
- [ ] Mac에서 테스트 및 호환성 확인

---

## 오케스트레이션 재설계 v2

> 배경: 기존 글로벌 CLAUDE.md의 "상황별 자동 제안" 규칙이 실제로 작동하지 않음(Claude가 알아서 제안을 거의 안 함). Codex/Gemini 활용도 저조. 진입점을 **사용자 호출 스킬**(`/codex`, `/gemini`)로 명시화하여 해결.

### 설계 원칙
- **철학**: Verification-First 유지. Claude가 주 실행자, 위임은 교차검증/협업 목적
- **진입점**: 사용자가 `/codex` 또는 `/gemini` 호출 → Claude가 맥락(git + 최근 대화) 기반으로 추천 메뉴 제시 → 사용자 선택 → 백그라운드 실행
- **AskUserQuestion 미사용**: enum 고정 → 활용처 제한. 자연어로 추천·응답
- **인프라 재활용**: plugin의 `codex-rescue`·`gemini-rescue` subagent와 `*-companion.mjs` 그대로 사용. 재발명 금지
- **협업 모드 내장**: triangulate / debate / cross-review 패턴으로 mesh 근사 (진짜 peer-to-peer는 기술적 불가, Claude 중재로 근사)

### v2.0 (완료, iteration 1)
- [x] `/codex`, `/gemini` 스킬 초안 작성 및 배포 (`~/projects/custom-skills/{codex,gemini}/`)
- [x] 기본 모델 지정: Codex=`gpt-5.4`, Gemini=`gemini-2.5-pro` (preview alias 금지)
- [x] Codex `adversarial-review` 자가 검증 실행 → 5개 high 심각도 지적 수신
- [x] Gemini triangulate 시도 실패 — mesh "collaboration theater" 위험 실증됨

### v2.1 (Codex 비평 반영, 완료)
- [x] `scripts/codex-dispatch.sh`, `scripts/gemini-dispatch.sh` wrapper 추가
  - Plugin cache internals 의존 제거 (Codex #4)
  - Plugin 업그레이드·경로 변경 시 wrapper만 수정
  - healthcheck 커맨드 포함 (companion + CLI 동작 확인)
- [x] Mesh 협업 모드(triangulate/debate/cross-review) 제거 (Codex #5 + Gemini 실증)
  - orchestration 계약(correlation/join/timeout/partial-failure) 정의 전까지 비활성
- [x] 스킬 맥락 수집 범위 확장 (Codex #2)
  - git status만 → 전체 대화 흐름 + diff stat + tool 출력 + 의도 포함
- [x] 실행 전 echo-confirm 규칙 추가 (Codex #3)
  - rescue(side-effect 가능)는 1줄 확인 후 실행
  - review/adversarial(read-only)은 즉시 실행

### v2.2 (완료)
- [x] Passive surfacing (Codex #1 부분 반영)
  - 고위험 맥락(migration/auth/crypto/security 파일 변경)에서 "/codex 교차검증 가능" 한 줄 정보 제공
- [x] `adapters/claude_global.md` 슬림화
  - 위임 매트릭스·Examples 삭제 → "/codex, /gemini 스킬 경유" 단일 안내
- [x] `adapters/claude.md`, `ROUTING_TABLE.md`의 Heavy-Delegation 잔재 제거
- [x] `bash scripts/sync.sh`로 ~/CLAUDE.md, ~/.codex/, ~/.gemini/ 재배포 (line budget 모두 통과)
- [ ] 불필요 plugin 스킬 `/skill-toggle` 정리 (`codex:codex-cli-runtime`, `codex:gpt-5-4-prompting`, `codex:codex-result-handling`) — 사용자 대화형 실행 필요

### v2.3 (완료, 2026-04-16)
- [x] **Context injection** — `codex-dispatch.sh` / `gemini-dispatch.sh` task·explore 호출 시 git root 기준 CLAUDE.md 자동 주입 (`--no-context`로 비활성화 가능)
- [x] **`explore` 모드** — read-only 조사. confirm 불필요. codex·gemini 양쪽 추가
- [x] **`resume` 모드** — Codex 전용. 마지막 task thread 이어서 실행 (`codex-dispatch.sh resume`, `--resume` 플래그)
- [x] **`last-thread` 커맨드** — resume 전 thread 정보 확인
- [x] **`wait` 커맨드** — 잡 완료 시 `<task-notification>` 발생 (올바른 완료 감지)
- [x] **rescue 결과 보고 후 resume 제안** — `claude_global.md`에 한 줄 규칙 추가
- [x] Codex review로 P2(CLAUDE.md 탐색 위치 버그) 발견·수정 — dispatch → git root 기준으로 개선
- [x] Gemini companion resume 미지원 확인 및 문서화

### v2.4 — 알림 회로 인프라 회복 (완료, 2026-04-26)

> 배경: `/codex` `/gemini` 스모크테스트에서 codex 완료 알림이 양쪽 채널 모두 막혀 있던 사실 발견. 추적 결과 plugin 경로 이동에 인프라가 따라가지 못해 누적된 silent failure.

- [x] **`codex-dispatch.sh wait`** 1·2차 fix — 옛 `os.tmpdir()/codex-companion` → `~/.claude/plugins/data/codex-openai-codex/state/`. tail-f|grep SIGPIPE hang을 1초 폴링으로 단순화
- [x] **`codex-dispatch.sh last-thread`** Windows 호환 — node `/dev/stdin` ENOENT 회피, JSON을 argv 전달
- [x] **`gemini-dispatch.sh` 컨텍스트 주입 포맷** — brief 우선·CLAUDE.md를 reference로 후미 첨부. Flash 모델이 짧은 brief를 컨텍스트 셋업으로 오인하던 회귀 해결
- [x] **proj launcher** `.ps1` shim 호환 — `Start-Process pwsh -NoLogo -NoProfile -Command <agent>` 래핑. `& <cmd>`의 fzf stdin 인헤리턴스 회귀(/codex review P2)도 동시 해결
- [x] **`job-watcher.mjs`** codex 블라인드 해소 — `CODEX_ROOTS` 배열로 새 plugin data 경로 우선 + 옛 temp-dir fallback. `extractMeta` 프로젝트 추출 일반화
- [x] **`scripts/sync.sh`** device 자동 배포 — `scripts/device/{job-watcher.mjs, job-watcher-inject.py}`를 `~/.claude/hooks/`에 자동 복사. 변경 감지 시 데몬 재시작 안내 출력 (강제 kill은 안 함)
- [x] **gemini 버전 글로브** — 하드코딩 `1.0.0` 제거, `geminiJobsDir()` 함수가 매 폴링마다 최신 버전 디렉토리 picking. plugin 업그레이드 내성

### v3 검토 대상 (미래)
- [ ] Mesh 협업 복원 — 계약 정의 후
  - per-leg correlation ID
  - join barrier + timeout
  - partial-failure 명시 보고 ("PARTIAL: X leg missing")
  - stale job ID 거부

### 검증 기준 (v2.1)
- `/codex`, `/gemini` 호출 시 현재 대화 흐름·git 상태 반영한 맥락 추천 3-5개 제시
- rescue 모드는 echo-confirm 후 실행
- Plugin 경로 직접 참조 없음 (wrapper 경유)
- 토큰 비용: Claude는 오케스트레이션만, 무거운 추론은 Codex/Gemini CLI 측

### 알려진 한계 및 의도된 트레이드오프
- 사용자가 "타이밍 잡아 호출"해야 함 — Verification-First 원칙상 의도적 포기
- Gemini가 복잡 멀티파트 프롬프트에 약함 — 단일 명확 질문으로 좁혀 보내야 함 (스킬에 문서화)

---

## K-IFRS 개인용 RAG/MCP 시스템

> **별도 프로젝트로 이전됨** → `~/projects/kifrs-rag/ROADMAP.md` (2026-04-14)

---

## 이어서 할 일

- M4(Mac)에서 `cd ~/projects/agent-orchestration && git pull && bash scripts/sync.sh` 실행해 device 자동 배포 + job-watcher 재시작 안내가 정상 출력되는지 확인. M4의 `~/.claude/hooks/job-watcher.mjs`가 새 코드로 교체된 뒤, 데몬 수동 재시작(`kill $(cat ~/.claude/hooks/.job-watcher.pid); node ~/.claude/hooks/job-watcher.mjs --detach`)으로 codex 알림이 Windows와 동일하게 동작하는지 확인.
