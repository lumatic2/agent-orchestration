# codex-mcp

## 개요

`codex-mcp`는 Codex CLI를 직접 호출하지 않고, `codex-companion.mjs`를 통해 MCP 도구로 노출하는 서버다. MCP 클라이언트는 이 서버를 통해 Codex 작업 enqueue, 상태 조회, 결과 수집, 취소를 수행할 수 있다.

## 설치

```bash
cd C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp
npm install
```

## 등록

```bash
claude mcp add codex-mcp -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
```

## 도구 목록

| 도구 | 설명 | 입력 스키마 |
| --- | --- | --- |
| `codex_task` | Codex 작업을 백그라운드로 enqueue | `prompt: string`, `write?: boolean = false`, `model?: 'default' \| 'spark'`, `effort?: 'low' \| 'medium' \| 'high'`, `resume?: boolean = false`, `fresh?: boolean = false`, `cwd?: string` |
| `codex_status` | job 상태 또는 전체 상태 조회 | `jobId?: string` |
| `codex_result` | 완료된 job 결과 수집 | `jobId: string` |
| `codex_cancel` | job 취소 | `jobId: string` |
| `codex_run` | enqueue → 자동 폴링 → 결과까지 한 번에 | `codex_task`와 동일 입력 + `pollIntervalMs?: number = 2000`, `timeoutMs?: number = 600000` |

## 내부 매핑

- `codex_task` → `task --background --json`
- `write: true` → `--write`
- `resume: true` → `--resume-last`
- `fresh: true` → `--fresh`
- `model: 'spark'` → `--model spark`
- `model: 'default'` → 플래그 생략
- `effort` → `--effort <value>`
- `cwd` 지정 시 → `--cwd <absolute-path>`
- `codex_status` → `status [job-id] --json`
- `codex_result` → `result <job-id> --json`
- `codex_cancel` → `cancel <job-id> --json`

## 환경 변수

### `CODEX_COMPANION_PATH`

기본값이 없으면 서버는 다음 경로 아래에서 가장 최신 semver 디렉토리를 찾아 `scripts/codex-companion.mjs`를 자동 선택한다.

```text
C:/Users/1/.claude/plugins/cache/openai-codex/codex/
```

특정 companion 파일을 강제로 사용하려면 절대 경로를 지정한다.

```bash
set CODEX_COMPANION_PATH=C:/custom/path/scripts/codex-companion.mjs
```

## 사용 예시

### 1. Read-only 분석 (기본 모델)

```jsonc
// codex_task
{
  "prompt": "scripts/sync.sh 구조 분석하고 개선점 3가지",
  "cwd": "C:/Users/1/Projects/agent-orchestration"
}
// → { "jobId": "task-...", "status": "queued", ... }
```

### 2. Write 모드 + spark/low (단순 보일러플레이트)

```jsonc
{
  "prompt": "scripts/new-util.sh 템플릿 생성",
  "write": true,
  "model": "spark",
  "effort": "low",
  "cwd": "C:/Users/1/Projects/agent-orchestration"
}
```

### 3. 이전 thread 이어서

```jsonc
{ "prompt": "앞 작업 이어서 테스트 추가", "write": true, "resume": true, "cwd": "..." }
```

### 4. Poll → Result

```jsonc
// codex_status
{ "jobId": "task-..." }
// → { "job": { "status": "running" | "completed", ... } }

// codex_result (status=completed 이후)
{ "jobId": "task-..." }
// → { "storedJob": { "result": { "rawOutput": "...", "touchedFiles": [...] }, "rendered": "..." } }
```

### 5. Auto-poll (`codex_run`) — 한 번 호출로 완결

```jsonc
// codex_run
{
  "prompt": "scripts/new-util.sh 템플릿 생성",
  "write": true,
  "cwd": "C:/Users/1/Projects/agent-orchestration",
  "pollIntervalMs": 2000,
  "timeoutMs": 600000
}
// → {
//   "jobId": "task-...",
//   "status": "completed" | "failed" | "timeout",
//   "elapsedMs": 36778,
//   "polls": 11,
//   "result": { /* codex_result 페이로드 그대로 */ }
// }
```

- 내부에서 `codex_task` → `codex_status` 루프 → `codex_result`를 한 번에 돌려 MCP 클라이언트의 폴링 루프를 제거한다.
- `timeoutMs` 초과 시 `status: "timeout"`, `result: null`을 반환하고 job은 **취소하지 않는다** — 필요하면 나중에 같은 `jobId`로 `codex_result`를 따로 호출해 수집 가능.
- `status: "failed"`는 companion이 실패 상태로 전이한 경우이며, 이때도 `codex_result`를 호출해 에러 상세를 `result`에 담아준다.
- 세밀한 중간 진행 상태가 필요하면 기존 `codex_task`/`codex_status`/`codex_result` 3-step을 계속 사용.

## 제한

- **Auto-poll 또는 3-step**: 기본은 `codex_run` 한 번으로 완결된다. 중간 진행 상태가 필요하거나 매우 긴 작업(타임아웃 초과)을 추적해야 할 때만 `task → status → result` 3-step을 사용한다.
- **Workspace-write sandbox**: `write: true`일 때 Codex는 호출 시점 `cwd` 내부만 수정 가능. 외부 경로를 수정하려면 `cwd`를 적절히 지정해야 한다.
- **Sandbox policy-blocked 명령**: Codex가 shell 실행이 막혔다고 판단하면 `rawOutput`에 해당 메시지를 넣고 status=0으로 종료한다. 실제 touchedFiles가 비어 있으면 "no-op 종료"로 간주.
- **Skill 플러그인과 같은 job 큐 공유**: `Skill("codex:rescue", ...)`와 `codex_task`는 동일 companion 프로세스/job store를 사용한다. 한쪽에서 등록한 job을 다른 쪽에서 `status`/`result`로 조회 가능. 반대로 동시 실행 시 순차 처리된다.
- **플러그인 경로 의존**: companion 경로가 `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` 형태로 존재해야 한다. 플러그인 미설치 시 서버 시작 실패.
