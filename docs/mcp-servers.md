# MCP Servers (방향 2)

> Codex CLI와 Gemini CLI를 Model Context Protocol 서버로 래핑해서 Claude Code / Cursor / Windsurf 등 어느 MCP 클라이언트에서도 "에이전트를 도구로" 부를 수 있게 만드는 방향 2의 프로토타입 구현 문서.

구현체: [`../mcp-servers/codex-mcp/`](../mcp-servers/codex-mcp/), [`../mcp-servers/gemini-mcp/`](../mcp-servers/gemini-mcp/)
배경: [`orchestration-roadmap.md`](./orchestration-roadmap.md) — 방향 2 "선정" 섹션

## 설계 원칙

1. **Thin shell-out 래퍼**: MCP 서버는 `codex-companion.mjs` / `gemini-companion.mjs`를 subprocess로 spawn할 뿐이다. 내부 job 관리·세션 resume·sandbox 매핑·AppServer 소켓 프로토콜을 재구현하지 않는다.
2. **플러그인 경로 격리**: companion 파일은 플러그인 캐시 아래 versioned 경로에 있다. MCP 서버는 최신 semver 디렉토리를 자동 탐색하며, env var(`CODEX_COMPANION_PATH`, `GEMINI_COMPANION_PATH`)로 override할 수 있다. 플러그인 업그레이드에 강한 경계.
3. **Enqueue + poll 패턴**: MCP 도구는 동기 응답이 원칙이라, 장시간 작업은 `*_task`(즉시 jobId 반환) → `*_status`(폴링) → `*_result`(완료 후 수집) 3-step으로 분리한다. Progress notifications는 클라이언트 지원 불균일로 v1 제외.
4. **Stdio transport**: Claude Code / Cursor / Windsurf 공통 지원.
5. **Node .mjs**: companion과 동일 런타임. TypeScript 컴파일 단계 제거.

## 아키텍처 다이어그램

```
┌─────────────────┐   MCP/stdio   ┌──────────────┐   spawn    ┌──────────────────────┐
│ Claude Code /   │ ─────────────▶│  codex-mcp   │ ─────────▶ │ codex-companion.mjs  │
│ Cursor /        │               │  gemini-mcp  │            │ gemini-companion.mjs │
│ Windsurf / ...  │◀───────────── │              │◀────────── │ (플러그인 캐시 경로)  │
└─────────────────┘   JSON-RPC    └──────────────┘  stdout/   └──────────────────────┘
                                                    exit code
```

- MCP 서버는 stdio 기반 JSON-RPC 어댑터 + 얇은 파서만 담당
- job queue, AppServer 소켓 프로토콜, thread resume 등 실제 상태 관리는 전부 companion 프로세스 쪽
- 동일 job store를 `Skill("codex:rescue", ...)` 등 기존 Skill 플러그인과 공유 → 공존 전제

## 도구 매핑

### codex-mcp

| MCP 도구 | 핵심 입력 | companion 매핑 |
|---|---|---|
| `codex_task` | prompt, write, model(default/spark), effort(low/med/high), resume, fresh, cwd | `task --background [--write] [--model X] [--effort Y] [--resume-last\|--fresh] -- <prompt>` |
| `codex_run` | `codex_task` 입력 + pollIntervalMs, timeoutMs | 내부적으로 `codex_task` → `codex_status` 반복 → `codex_result` |
| `codex_status` | jobId? | `status [jobId] --json` |
| `codex_result` | jobId | `result <jobId> --json` |
| `codex_cancel` | jobId | `cancel <jobId> --json` |

### gemini-mcp

| MCP 도구 | 핵심 입력 | companion 매핑 |
|---|---|---|
| `gemini_task` | prompt, model(flash/pro), background | `task [--background] [--model X] <prompt>` |
| `gemini_run` | `gemini_task` 입력 + pollIntervalMs, timeoutMs (`background`는 항상 true로 강제) | 내부적으로 `gemini_task` → `gemini_status` 반복 → `gemini_result` |
| `gemini_status` | jobId? | `status [jobId]` |
| `gemini_result` | jobId | `result <jobId>` |
| `gemini_cancel` | jobId | `cancel <jobId>` |

상세 스키마와 사용 예시는 각 서버의 README 참조.

## 등록 방법

### Claude Code

```bash
claude mcp add codex-mcp -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
claude mcp add gemini-mcp -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

Claude Code 재시작 후 `mcp__codex-mcp__codex_task` / `mcp__gemini-mcp__gemini_task` 형태로 노출된다.

### Cursor

`~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "codex-mcp":  { "command": "node", "args": ["C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs"] },
    "gemini-mcp": { "command": "node", "args": ["C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs"] }
  }
}
```

### Windsurf / Continue / 기타

동일한 `command` + `args` 페어를 각 클라이언트의 MCP 설정에 추가한다. 현재 Claude Code 외 클라이언트에서 실제 E2E 검증은 수행하지 않았다 — 후속 작업.

## 기존 Skill 플러그인과의 관계

`codex:rescue` / `gemini:rescue` Skill 플러그인과 MCP 서버는 **공존**한다.

| 축 | Skill 플러그인 | MCP 서버 |
|---|---|---|
| 호출 주체 | Claude Code 전용 | 모든 MCP 클라이언트 |
| 인터페이스 | `Skill` 도구 + 프롬프트 팩 | JSON-RPC 도구 호출 |
| Job store | 동일 companion 디렉토리 공유 | 동일 companion 디렉토리 공유 |
| 장점 | Claude Code 관례(`--background --write` 등) 내장, 세션 컨텍스트 자동 전달 | 다중 클라이언트, 에이전트 간 체이닝 가능 |

양쪽에서 등록한 job은 상대편에서 `status`/`result`로 조회 가능함이 Phase 4 스모크 테스트에서 확인됐다. 한쪽 deprecate 결정은 실사용 데이터가 더 쌓인 후에 내린다.

## 현재 상태 (2026-04-08)

- [x] Phase 1: 스캐폴딩 + SDK 조사
- [x] Phase 2: codex-mcp 구현
- [x] Phase 3: gemini-mcp 구현
- [x] Phase 4: Claude Code 등록 + 스모크 테스트 (codex 왕복, gemini 왕복, Skill 공존 확인)
- [x] Phase 4 hotfix: `gemini-exec.mjs`의 `runCompanion`이 JSON.parse로 plain-text 응답을 삼키던 버그 수정, `parseResultOutput` output 필드 trim
- [x] Phase 5: 문서화 (본 문서 + 각 서버 README 사용 예시/제한 섹션)
- [x] Phase 6: Auto-poll wrapper (`codex_run` / `gemini_run`) — `*_task → status 폴링 → result` 3-step을 한 번의 도구 호출로 감쌈. 스모크: `codex_run` 왕복 36.7s / 11 polls (completed), `gemini_run` 왕복 45s / 15 polls, `timeoutMs: 3000` 강제 시 `status: "timeout"` + jobId 보존 검증, 기존 `codex_task` 회귀 없음

## 후속 개선 (Open Items)

### 1. 다른 MCP 클라이언트에서 실사용 검증

Cursor / Windsurf / Continue에 등록 → 도구 호출 왕복 확인 → 각 클라이언트 특유 제약 문서화.

### 2. Progress notifications / streaming

MCP 표준의 progress notifications가 주요 클라이언트에 안착하면 `*_task`를 sync 호출로 전환하고 중간 진행 상황을 stream으로 내보내는 방안 검토. v1 이후.

### 3. Cwd sandbox 검증 강화

현재 `codex_task`의 `cwd`는 문자열 그대로 companion에 넘긴다. workspace-write sandbox 경계를 MCP 서버 레벨에서 한 번 더 validation하면 의도치 않은 경로 수정을 더 일찍 차단할 수 있다.

### 4. Multi-agent 체이닝 예시 (방향 1/3의 씨앗)

- [x] **방향 1 — 적대적 리뷰 체인** (2026-04-08): Claude의 tool calling으로 `codex_run` → `gemini_run`(리뷰) → Claude 심판 → `codex_run`(resume) 체인을 1회 완주. 1차 코드의 silent-wrong-answer 4개를 리뷰가 잡고 2차에서 explicit ValueError로 전환됐다. 세션 기록 [`../examples/adversarial-review.md`](../examples/adversarial-review.md), 복붙 템플릿 [`../examples/adversarial-review-template.md`](../examples/adversarial-review-template.md). 부수 발견: gemini-3-flash-preview hang 빈도가 높아 fallback 경로(Claude 직접 리뷰)를 기본 보험으로 명시함, codex-companion이 spark 모델 작업 후 finalizing 단계에서 멈추는 현상 관찰됨.
- [ ] **방향 3 — Deep Research 루프**는 별도 스텝(플랜 Step 4)에서 진행.

## A2A — Codex/Gemini를 MCP 클라이언트로 (Step 3, 2026-04-08)

지금까지 codex-mcp / gemini-mcp는 Claude Code가 유일한 클라이언트였다. **Codex CLI와 Gemini CLI 양쪽 다 MCP 클라이언트 모드를 네이티브 지원**한다는 사실이 확인돼, Codex 세션에서 gemini-mcp를 직접 호출하고 그 반대도 동작하는 진짜 A2A 구조를 검증했다.

### Codex CLI ← gemini-mcp 등록

```bash
codex mcp add gemini-mcp node C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

`~/.codex/config.toml`에 `[mcp_servers.gemini-mcp]` 섹션이 자동 추가된다 (TOML 스키마: `command`, `args`, optional `env`/`startup_timeout_sec`, HTTP transport는 `url` + `bearer_token_env_var`). `[features] rmcp_client = true`가 켜져 있어야 한다 (이미 ON).

**Codex 세션에서 노출되는 도구** (왕복 검증 완료):
- `gemini_task`, `gemini_run`, `gemini_status`, `gemini_result`, `gemini_cancel`

### Gemini CLI ← codex-mcp 등록

```bash
gemini mcp add --scope user --trust codex-mcp node C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
```

`~/.gemini/settings.json`의 `mcpServers` 객체에 추가된다. `--trust`로 등록하면 도구 호출 승인 prompt가 생략된다 (서버 단위 신뢰 — 비대화 모드 필수). `--include-tools`/`--exclude-tools`로 노출 도구 화이트리스트도 가능.

### 왕복 검증 (2026-04-08)

| 방향 | 호출 | 결과 |
|---|---|---|
| Codex → gemini-mcp → gemini CLI | `gemini_task(prompt="hi", model="flash")` | `jobId: g-760f9f24` 즉시 반환, turn.completed |
| Gemini → codex-mcp → codex CLI | `codex_task(prompt="Say hello world", cwd=...)` | `jobId: task-mnq3shrx-k414a8` 즉시 반환, 25s 후 completed (summary "hello world") |

### 비대화 모드 제약 (중요)

- **Codex `codex exec` 비대화 모드에서 MCP 도구를 호출하려면 `--dangerously-bypass-approvals-and-sandbox` 플래그가 필요**하다. `approval_policy = "never"` + `sandbox_mode = "danger-full-access"`만으로는 MCP tool call이 자동 `user rejected MCP tool call`로 끊긴다. MCP tool approval은 셸 명령 approval과 별개 게이트.
- Gemini는 서버 등록 시 `--trust` 플래그로 동일 문제 우회.
- 부수 관찰: Codex가 세션 시작 시 `resources/list`를 자동 호출하는데, 두 MCP 서버 모두 해당 메서드 미구현이라 `-32601 Method not found` warning이 한 줄 찍힌다. 도구 호출 자체에는 영향 없음. → 후속 개선 #5 참조.

### 순환 호출 방지

업스트림 MCP 표준에는 cycle detection 메커니즘이 없다 (조사 시점 2026-04, 보강 필요). 현재는 **운영 규칙 + 구조적 차단** 조합:

1. **Self-loop 금지 (구조적)**: codex-mcp는 codex CLI를 spawn → Codex config에 절대 등록하지 않는다. gemini-mcp ↔ Gemini도 동일. (자기 자신을 부르면 즉시 무한 재귀.)
2. **Cross-loop 차단 (운영)**: Codex ← gemini-mcp, Gemini ← codex-mcp 양쪽이 등록된 상태에서 A→B→A→B 재귀가 가능. 1차 방어는 "체이닝의 최상위 오케스트레이터는 한 명"이라는 규칙 — Claude/Codex/Gemini 중 한 에이전트가 driver가 되고, driver가 호출하는 worker는 다시 driver를 부르지 않도록 프롬프트에 명시.
3. **2차 방어 (구현 완료, 후속 개선 #6)**: codex-mcp / gemini-mcp가 `ORCH_MCP_DEPTH` env var를 읽어 N≥2 도달 시 `codex_task`/`codex_run`/`gemini_task`/`gemini_run`을 거부하고, spawn하는 companion child env에 depth+1을 주입한다. 기본 임계값 2 (Claude→A→B 2홉 허용, A→B→A 차단). 한도 조정은 최상위 오케스트레이터에 `ORCH_MCP_DEPTH_LIMIT`로.

### 5. ~~resources/list 미구현 경고~~ — 완료 (2026-04-08)

두 서버(`mcp-servers/{codex,gemini}-mcp/src/index.mjs`)에 빈 `resources/list` + `resources/templates/list` 핸들러 추가. SDK의 high-level `McpServer` 대신 low-level `server.server.setRequestHandler`로 바로 등록(`McpServer.registerResource`는 dummy URI를 강요해서 부적합). Codex CLI 세션 시작 시 떴던 `-32601 Method not found` warning 사라짐.

### 6. ~~ORCH_MCP_DEPTH cycle counter~~ — 완료 (2026-04-08)

두 MCP 서버(`mcp-servers/{codex,gemini}-mcp/src/{codex,gemini}-exec.mjs`)에 모듈 레벨 헬퍼 `currentDepth()` / `depthLimit()` / `enforceDepthLimit(toolName)`을 추가했다.

- **읽기**: `process.env.ORCH_MCP_DEPTH` (없으면 0). 한도는 `ORCH_MCP_DEPTH_LIMIT` (없으면 default 2).
- **체크**: `*_task` / `*_run` 진입 시 `enforceDepthLimit` — `depth >= limit`이면 즉시 throw. `*_status` / `*_result` / `*_cancel`은 새 에이전트 호출이 아니라 메타데이터 op이므로 게이트하지 않음.
- **전파**: `runCompanion` 안에서 spawn 직전에 `childEnv.ORCH_MCP_DEPTH = String(currentDepth()+1)`. 환경변수가 자연스럽게 codex/gemini CLI → 새 MCP client child까지 inherit되어 다음 홉이 한 단계 증가된 depth로 시작한다.
- **기본 의미**: limit 2 → 0(top, Claude)→1(첫 spawn, A)→2(두 번째 spawn, B). 깊이 2에 도달한 B 안에서 다시 A를 부르려 하면 spawn된 A가 depth=2를 보고 거부 (`>= 2`). 즉 Claude→A→B 2 홉 허용, Claude→A→B→A 차단.

**검증** (2026-04-08):

| 케이스 | 환경변수 | 결과 |
|---|---|---|
| 거부 (codex) | `ORCH_MCP_DEPTH=2` | `Error: ORCH_MCP_DEPTH limit exceeded: depth=2, limit=2 ...` |
| 거부 (gemini) | `ORCH_MCP_DEPTH=2` | 동일 메시지 (`gemini_task`) |
| 통과 (codex) | `ORCH_MCP_DEPTH=1` | jobId 정상 반환 (`task-mnq5e6r8-numa8e`) |
| 한도 override | `ORCH_MCP_DEPTH=4 ORCH_MCP_DEPTH_LIMIT=5` | jobId 정상 반환 |

A2A 풀체인 (Claude→codex→gemini→codex 시도) 검증은 별도 세션에서 실증 가능하나, 단위 동작이 모두 통과해서 등가 효과로 본다.

### 7. codex-companion `cancel`/`terminateProcessTree` upstream bug (2026-04-08, 업스트림 보고 2026-04-09)

**업스트림 이슈**: [openai/codex-plugin-cc#182](https://github.com/openai/codex-plugin-cc/issues/182)

플러그인 캐시 `1.0.3/scripts/lib/process.mjs`의 `runCommand`가 Windows에서 `shell: process.env.SHELL || true`로 spawnSync를 호출한다. `SHELL`이 Git Bash를 가리키면 MSYS path conversion이 동작해서 `terminateProcessTree`가 부르는 `taskkill ["/PID", pid, "/T", "/F"]`의 옵션 토큰들이 `C:/Program Files/Git/PID 12345 C:/Program Files/Git/T C:/Program Files/Git/F`로 변환되고, taskkill이 옵션을 인식하지 못해 cancel이 실패한다.

**우리 layer 워크어라운드** (`mcp-servers/codex-mcp/src/codex-exec.mjs:runCompanion`): MCP 서버가 codex-companion을 spawn할 때 child env에서 `SHELL`을 strip → companion 내부의 spawnSync가 cmd.exe fallback을 쓰게 강제 → MSYS 변환 발생 안 함. 검증: `taskkill /PID 68400 /T /F` 정상 형태로 호출 확인.

**잔여 upstream 이슈 두 건** (보고 필요):
1. **로케일 의존 regex**: `looksLikeMissingProcessMessage`가 영어 패턴(`/not found|no running instance|cannot find|...`)만 검사. Windows 한국어 로케일의 "프로세스를 종료할 수 없습니다" / "찾을 수 없습니다" 같은 메시지에 매치 안 됨 → 이미 죽은 프로세스를 kill 시도해도 `throw new Error(formatCommandFailure(...))`로 cancel 전체를 실패 처리.
2. **spawnSync `shell: SHELL` 자체**: Git Bash 환경에서 인자 의도를 깨는 1번 원인. `shell: false`로 쓰고 `taskkill.exe`를 직접 spawn하는 게 안전.

### 8. codex-companion `runTrackedJob` 무한 대기 (B-1 finalizing hang, 2026-04-08, 업스트림 보고 2026-04-09)

**업스트림 이슈**: [openai/codex-plugin-cc#183](https://github.com/openai/codex-plugin-cc/issues/183)

**증상**: spark 모델 짧은 작업 후 또는 cancel 호출 후, job이 `status: "running"` + `phase: "finalizing"` 상태로 영원히 남음. 좀비 job이 다음 `--resume`을 막음.

**Root cause**: `1.0.3/scripts/lib/tracked-jobs.mjs:142` `runTrackedJob`이 `await runner()`만 호출하고 자체 타임아웃이 없음. `runner` 안의 `executeTaskRun` → `captureTurn` (`scripts/lib/codex.mjs`)이 AppServer notification (`turn/completed` 또는 `final_answer` phase의 `item/completed`)을 기다리며 promise를 반환. 어떤 경로로든 그 notification이 영영 안 오면 promise는 pending인 채로 남고, try/catch도 fire되지 않아 job 파일이 terminal state로 전환되지 않는다.

**관찰된 트리거**:
- Cancel 호출 시: `interruptAppServerTurn`이 RPC interrupt를 보내지만 AppServer가 `turn/completed (status=interrupted)`를 emit하지 않거나 worker가 그 메시지를 받기 전에 끊김 → captureTurn pending
- Spark 모델 정상 완료 시: 사용자 관찰. 가설 — spark의 응답 stream에서 `final_answer` phase가 다른 형태로 표기되거나 누락 → `state.finalAnswerSeen = false` → `scheduleInferredCompletion` 미발동 → captureTurn pending

**우리 layer 워크어라운드 가능성**: 직접 fix 없음. companion의 job store 디스크 포맷에 의존해서 stale-job GC를 우리 MCP 서버에 넣는 방안은 plugin upgrade에 깨질 위험이 커서 보류. 운영 규칙으로 처리:
- 좀비 job이 발견되면 `~/.codex/`나 companion job store를 직접 정리하지 말고, 새 thread로 진행 (`--fresh`)
- 동일 워크스페이스에서 `--resume` 막힘이 반복되면 codex-companion 로그/job 디렉토리를 사용자가 수동으로 wipe

**필요한 upstream 패치** (보고 필요):
1. `runTrackedJob`에 hard timeout 옵션 추가 (예: `taskTimeoutMs`, default 15분, 초과 시 `failed` + `phase: "timeout"`로 전환)
2. `captureTurn`에 마지막 progress 후 N초 idle 감지 → `failed (no notifications)` fallback
3. AppServer interrupt 후 worker가 일정 시간 내 종료 못 하면 강제 reject

### 9. `gemini_run` output validation — 빈 문자열/trailing error 미감지 (2026-04-09, Step 4a Session 1 실증)

**증상** (두 갈래):
1. **빈 문자열 → status: "completed"**: Gemini CLI 가 spawn한 외부 터미널 창을 사용자가 수동으로 닫으면 해당 branch 가 `output: ""`으로 즉시 반환되는데 MCP wrapper는 이걸 성공으로 보고. Deep Research B 루프 Session 1 에서 사용자가 "뭔지 모를 창" 3 개를 닫아 3/3 branch 가 조용히 실패했다.
2. **Trailing error dump appended to valid output**: `gemini_run(model="pro")` 호출에서 pro 가 본문 생성 후 WebSearch grounding tool 이 내부적으로 flash 를 호출하며 429 (`MODEL_CAPACITY_EXHAUSTED`)를 맞으면 그 error dump 가 `output` 문자열 뒤에 append 된다. 본문은 멀쩡해도 하위 파서 (Skeptic 에 전달하는 Claude Judge 등)가 trailing JSON/stacktrace 를 원 리서치 내용으로 오인할 위험.

**Root cause**: `mcp-servers/gemini-mcp/src/gemini-exec.mjs` 의 result 수집이 stdout 전문을 그대로 `output` 필드에 넘긴다. (1) 빈 문자열 검사 없음, (2) trailing stacktrace / 429 body 분리 없음.

**필요한 패치** (추정):
1. Empty output guard: `output.trim().length === 0` 이면 `status: "failed"` + `error: "empty output — likely terminal closure or upstream no-op"` 로 래핑. `available: false` 를 이미 쓰고 있는 `found`/`available` 필드와 정렬.
2. Trailing error detection: stdout 에 `_GaxiosError` / `Attempt \d+ failed with status` / `"MODEL_CAPACITY_EXHAUSTED"` 같은 signature 가 있으면 본문과 분리해서 별도 `warnings[]` 필드로 옮김. 본문만 `output` 에 남김. signature 가 본문 시작 부분에 있으면 (생성 전 실패) `status: "failed"`.
3. Same for Gemini CLI 의 "Health Check OK" 류 placeholder — 프롬프트 무시하고 정상 응답인 척 placeholder 를 뿜을 때 signature 감지.

**실측 관찰**:

| 케이스 | output 상태 | 현재 wrapper | 기대 동작 |
|---|---|---|---|
| 사용자 창 닫음 | `""` (2.7s) | `status: completed` | `status: failed`, reason=`empty-output` |
| pro 본문 + trailing 429 | 본문 50KB + error dump 5KB | `output` 에 통째 | `output` = 본문만, `warnings[]` 에 dump |
| 429 후 placeholder ("Health Check OK") | placeholder 3 줄 + error dump | `status: completed` | `status: failed`, reason=`placeholder-output` (의심 signature 검출) |

**Deep Research B 루프에의 영향**: output validation 이 없으면 루프가 빈 결과를 정답으로 수용하고 coverage 가 왜곡된다 → Judge 단계의 claim 생존 판정이 쓸모없어짐. Step 4a 실증에서 체인 전체가 조용히 죽을 뻔했음 (첫 시도 3/3 빈 출력 → 사용자가 알아차림). 후속 Session 2 전에 패치 권장.

**관련**: `examples/deep-research-template.md` 에 Windows 사용자 경고를 추가했지만 이건 workaround 일 뿐, root fix 는 이 항목.

### 10. `gemini_run` 서버 capacity 부족 시 URL fabrication — Skeptic-only 탐지 가능 (2026-04-09, Step 4a Session 2 실증)

**증상**: Gemini (pro/flash 모두) 가 `MODEL_CAPACITY_EXHAUSTED` (server-side capacity 부족) 을 맞으면 grounding tool call 이 실패하고, Gemini CLI 가 retry loop 를 끝낸 뒤 **training data 만으로 응답을 조합**한다. 그 과정에서:
1. 날짜 필터 (2024년 이후) 를 무시하고 2023년 이전 소스를 인용
2. **존재하지 않는 URL 을 생성** — slug 가 `0f1b1b1b1b1b` 처럼 반복되는 패턴, 혹은 저자 핸들 + 제목-슬러그 조합의 가짜 Medium/Substack URL

**Root cause** (추정): Gemini CLI 의 grounding fallback behavior — Web search 가 실패하면 조용히 비활성화된 채로 응답을 계속 생성. MCP wrapper 는 이 상태를 **감지할 수 없다** (stdout 에 429 signature 가 남으면 #9 에서 잡히지만, CLI 가 retry 후 깔끔하게 종료하면 wrapper 는 `status: completed` 로 받음).

**실증 데이터** (Session 2 Branch C retry):
- 반환 URL: `https://medium.com/@shashankguda/challenges-criticisms-of-langchain-0f1b1b1b1b1b` → 명백한 hallucination (slug 반복)
- 반환 URL: `minimaxir.com/2023/07/langchain-problem/` → 날짜 필터 (2024+) 위반
- Gemini 가 응답 말미에 **스스로** "429 로 재시도 실패, 응답 중도 절단" 이라고 자백 — content-level self-report 이므로 wrapper 가 못 잡음

**탐지 전략** (wrapper 레벨 불가, 루프 레벨에서 해결):
1. **Skeptic 단계에서 URL verification 필수**: Deep Research B 루프의 Codex Skeptic 은 Proposer 가 제공한 모든 primary URL 을 실제로 fetch/validate 해야 한다. fake URL 은 404, 혹은 실제 존재하는 URL 이어도 본문이 claim 과 무관하면 drop.
2. **Date filter 재검증**: Skeptic 은 "2024년 이후" 같은 scope 제약을 Proposer 응답에 소급 적용해야 한다.
3. **Branch position effect 병행 관찰** (#11 참조): 3 branch 병렬 발사 시 첫 branch 는 정상인 경우가 많음 → 두 번째부터 의심 강화.

**Deep Research B 루프에의 영향**: CRITICAL. 이 버그가 Skeptic 으로 필터되지 않으면 최종 보고서가 존재하지 않는 소스를 인용하는 가짜 리서치가 된다. 실제로 Session 2 는 이 이유로 재현성 run 을 통째로 폐기했다. Skeptic 프롬프트 (`research-skeptic.md`) 에 "fabricated URL 탐지" 를 명시적으로 추가 필요.

**재현성**: 2026-04-09 오후 Windows 환경, agent framework 주제 (blog/github heavy) 에서 2회 연속 재현. 같은 날 아침 Q1 (arxiv heavy) 에서는 미발생 — 주제 도메인에 따라 grounding load 가 달라 capacity 소진 빈도가 다를 가능성 (→ #11).

### 11. `gemini_run` branch position effect — 첫 branch 특권 가설 (2026-04-09, Step 4a Session 2 관찰)

**증상**: 3 branch 병렬 발사 시 **position 0 (첫 branch)** 는 정상 완료되고, position 1/2 (후속 branch) 는 `MODEL_CAPACITY_EXHAUSTED` 로 축약되는 패턴. Session 2 에서 2 run × 3 branch = 6 개 관찰 중 정상 2건 (둘 다 position 0), 축약 4건 (position 1/2).

**가설** (미검증):
1. Gemini CLI 내부 quota pool 이 프로세스/세션 단위로 관리되고, 병렬 호출 시 pool 이 빠르게 소진됨
2. Google 서버측 per-account rate limit 이 burst 로 친 호출 중 late-arriving ones 을 reject
3. 단순히 random coincidence — n=6 으로는 확정 불가

**실측 필요**:
- position effect 를 통제하려면 병렬 발사 간격을 두고 sequential 로 발사 (`--background` 간 20-30초 sleep) → 재현성 비교
- 혹은 session 을 분리 (branch 마다 별도 claude-code 세션) → 동일 증상 나오는지

**현재 workaround**: 3 branch 를 sequential 로 발사하고 각 사이에 status 확인. 대신 **루프 latency 2-3배 증가** (parallel 의 이점 상실).

**Deep Research B 루프에의 영향**: MEDIUM. 재현성 측정 run 에서 branch 3 개의 품질이 비대칭이면 Skeptic 의 coverage metric 해석이 왜곡된다. Session 2 에서 실제로 이 이유로 run 을 폐기했다. Session 3 재시도 전에 branch 발사 전략 재검토 필요.

**관련**: #10 (URL fabrication) 과 같은 근본 원인 (capacity exhaustion) 일 가능성 높음 — 위치가 다를 뿐.
