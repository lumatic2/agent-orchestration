# Agent Orchestration

> Claude Code · Codex · Gemini 멀티에이전트 협업 시스템. **Verification-First** 원칙 기반.

## 철학: Verification-First

**Claude Code가 주 실행자**. 코드 편집, 파일 분석, 계획 수립, WebSearch까지 직접 수행한다.

Codex / Gemini 위임은 **노동 분담이 아닌 교차검증 목적**으로만 사용한다:
- 독립 모델 관점으로 할루시네이션 감소
- 설계·가정에 대한 adversarial review
- Google 인덱스 기반 사실 검증 (Gemini)
- 2M+ 초장문 컨텍스트 분석 (Gemini)

**자동 위임 없음.** 호출 타이밍은 사용자가 판단한다. Claude는 고위험 맥락(migration/auth/crypto/security)에서만 답 끝에 "`/codex` 교차검증 가능" 한 줄을 흘릴 뿐, 알아서 위임하지 않는다.

## 진입점

모든 외부 에이전트 호출은 **사용자 호출 슬래시 스킬** 경유:

| 스킬 | 용도 | 모드 |
|---|---|---|
| `/codex` | 코드 리뷰, 설계 도전, 조사·구현 위임 | `review` · `adversarial-review` · `explore` · `task` · `resume` |
| `/gemini` | 최신성 fact-check, 대용량 문서, 독립 리서치 | `research` · `review` · `factcheck` · `explore` · `task` |
| `/openclaw` | 브라우저·GUI·텔레그램 (M4 원격) | — |

스킬이 현재 맥락(git 상태, 최근 대화, diff)을 수집해 **3~5개 추천 메뉴**를 제시하고, 사용자가 고른 모드를 **background + 실패 허용**으로 실행한다.

- `rescue` / `task` (side-effect 가능): 1줄 echo-confirm 후 실행
- `review` / `adversarial-review` / `explore` (read-only): 즉시 실행

## 실행 계층

```
User
 │
 ▼
Claude Code  ────────────────── 직접 실행 (코드 편집, 분석, 판단)
 │
 ├─ /codex   → scripts/codex-dispatch.sh  → codex-companion  → Codex CLI  (gpt-5.4 / 5.3)
 ├─ /gemini  → scripts/gemini-dispatch.sh → gemini-companion → Gemini CLI (2.5-pro / 2.5-flash)
 └─ /openclaw → SSH m4 → OpenClaw (브라우저·canvas·JS 렌더링·세션)
```

**dispatch wrapper**가 플러그인 내부 경로 변경을 흡수한다:
- `task` / `explore` 호출 시 **git root의 `CLAUDE.md` 자동 주입** (`--no-context`로 비활성화)
- 모든 호출에 `--background` 자동 부여
- `codex-dispatch.sh resume` — 직전 task thread 이어서 실행 (Codex 전용)
- `codex-dispatch.sh wait <job-id>` — 완료 시 `<task-notification>` 발행

## 책임 분리

| 역할 | 담당 |
|---|---|
| **Claude** | 주 실행자. 편집·분석·계획·직접 검색. 오케스트레이션 판단 |
| **Codex** | 독립 관점 리뷰, adversarial, 사용자가 명시 위임한 구현·조사 |
| **Gemini** | Google 인덱스 fact-check, 최신성 리서치, 2M+ 문서 요약 |
| **OpenClaw** | 브라우저 자동화, 로그인 세션, 차트 렌더, JS SPA 크롤링 |

자세한 의사결정 플로우: [`ROUTING_TABLE.md`](./ROUTING_TABLE.md)

## Quick Start

```bash
# 동기화 상태 확인
bash scripts/sync.sh --check

# adapters/ 변경을 ~/CLAUDE.md, ~/.codex/, ~/.gemini/ 로 배포
bash scripts/sync.sh

# dispatch 헬스체크
bash scripts/codex-dispatch.sh health
bash scripts/gemini-dispatch.sh health

# 다른 프로젝트에 Codex용 AGENTS.md stub 생성 (CLAUDE.md 자동 참조)
bash scripts/init-project-agents.sh
```

## 구조

```
adapters/
  claude_global.md       ~/CLAUDE.md 원본 (sync.sh가 배포)
  codex_home.md          ~/AGENTS.md 원본 (Codex 홈 스코프, 전역 로드)
  gemini.md              ~/.gemini/GEMINI.md 원본

scripts/
  sync.sh                adapter → 각 에이전트 홈으로 배포
  codex-dispatch.sh      Codex 호출 안정화 래퍼
  gemini-dispatch.sh     Gemini 호출 안정화 래퍼
  guard.sh               파괴적 명령 차단 훅
  init-project-agents.sh 타 프로젝트용 AGENTS.md stub 생성

mcp-servers/
  codex-mcp/             Codex CLI을 감싼 MCP 서버 (legacy 경로)
  gemini-mcp/            Gemini CLI을 감싼 MCP 서버 (legacy 경로)

agent_config.yaml        모델 티어, 복잡도 분류, 폴백 체인
ROUTING_TABLE.md         작업 → 에이전트 라우팅 결정표
ROADMAP.md               마일스톤과 설계 의사결정 이력

examples/
  adversarial-review-template.md
  deep-research-template.md
  openclaw-browser-template.md
```

> MCP 서버는 초기 구조의 잔재다. 현재 표준은 `/codex`, `/gemini` 스킬 + dispatch wrapper이며, MCP tool 직접 호출은 권장하지 않는다.

## 모델 티어

`agent_config.yaml`에서 복잡도별 모델을 선택한다.

| 복잡도 | Codex | Gemini | Claude |
|---|---|---|---|
| low | `gpt-5.3-codex-spark` | `gemini-2.5-flash-lite` | haiku |
| medium | `gpt-5.3-codex` (high) | `gemini-2.5-flash` | sonnet |
| high | `gpt-5.3-codex` (high) | `gemini-2.5-flash` | sonnet (high) |
| ultra | `gpt-5.4` (xhigh) | `gemini-2.5-pro` | opus |

## 멀티 기기

git으로 동기화. 다른 기기에서 pull 후 `bash scripts/sync.sh` 실행.

기기별 수동 설치(래퍼·로컬 경로 등)는 `scripts/device/` 참조.

## 알려진 트레이드오프

- **사용자가 호출 타이밍을 잡아야 함.** Verification-First 원칙상 의도적 포기.
- **Gemini는 복잡 멀티파트 프롬프트에 약함.** 단일 명확 질문으로 좁혀 보낸다.
- **Mesh 협업(triangulate/debate) 비활성.** "collaboration theater" 방지 위해 제거. per-leg correlation ID / join barrier / partial-failure 보고 등 orchestration 계약 정의 전까지 복원 보류.
