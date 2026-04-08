# gemini-mcp

## 개요

`gemini-mcp`는 Gemini CLI를 직접 호출하지 않고, `gemini-companion.mjs`를 통해 MCP 도구로 노출하는 서버다. MCP 클라이언트는 이 서버를 통해 Gemini 작업 실행, 상태 조회, 결과 수집, 취소를 수행할 수 있다.

## 설치

```bash
cd C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp
npm install
```

## 등록

```bash
claude mcp add gemini-mcp -- node C:/Users/1/Projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

## 도구 목록

| 도구 | 설명 | 입력 스키마 |
| --- | --- | --- |
| `gemini_task` | Gemini 작업 실행 또는 백그라운드 enqueue | `prompt: string`, `model?: 'flash' \| 'pro'`, `background?: boolean = true` |
| `gemini_status` | job 상태 또는 최근 job 목록 조회 | `jobId?: string` |
| `gemini_result` | 완료된 job 결과 수집 | `jobId: string` |
| `gemini_cancel` | job 취소 | `jobId: string` |
| `gemini_run` | enqueue → 자동 폴링 → 결과까지 한 번에 (background 강제) | `prompt: string`, `model?: 'flash' \| 'pro'`, `pollIntervalMs?: number = 2000`, `timeoutMs?: number = 600000` |

## 내부 매핑

- `gemini_task` → `task [--background] [--model <flash|pro>] <prompt>`
- `background: true` → `--background`
- `background: false` → 포그라운드 동기 실행
- `model: 'flash'` → `--model flash`
- `model: 'pro'` → `--model pro`
- `gemini_status` → `status [job-id]`
- `gemini_result` → `result <job-id>`
- `gemini_cancel` → `cancel <job-id>`

## 환경 변수

### `GEMINI_COMPANION_PATH`

기본값이 없으면 서버는 다음 경로 아래에서 가장 최신 semver 디렉토리를 찾아 `scripts/gemini-companion.mjs`를 자동 선택한다.

```text
C:/Users/1/.claude/plugins/cache/claude-gemini-plugin/gemini/
```

특정 companion 파일을 강제로 사용하려면 절대 경로를 지정한다.

```bash
set GEMINI_COMPANION_PATH=C:/custom/path/scripts/gemini-companion.mjs
```

## 사용 예시

### 1. Flash — 가벼운 질문 (background)

```jsonc
// gemini_task
{ "prompt": "1+1=? 숫자만 답해.", "model": "flash" }
// → { "jobId": "g-...", "mode": "background", ... }
```

### 2. Pro — 심층 분석

```jsonc
{
  "prompt": "첨부한 논문 요약해서 핵심 주장 3개 뽑아줘: ...",
  "model": "pro"
}
```

### 3. Poll → Result

```jsonc
// gemini_status
{ "jobId": "g-..." }
// → { "status": "running" | "completed", "model": "...", "startedAt": "..." }

// gemini_result (status=completed 이후)
{ "jobId": "g-..." }
// → { "found": true, "available": true, "output": "정리된 본문 텍스트", "raw": "..." }
```

### 4. 포그라운드 동기 실행 (짧은 질문 한정)

```jsonc
{ "prompt": "오늘 날짜가 뭐야?", "model": "flash", "background": false }
// → { "mode": "foreground", "output": "...", "raw": "..." }
```

Foreground 호출은 MCP 클라이언트가 수십초~15분까지 블록될 수 있으므로 짧은 질문 외에는 권장하지 않는다.

### 5. Auto-poll (`gemini_run`) — 한 번 호출로 완결

```jsonc
// gemini_run
{
  "prompt": "1+1=? 숫자만 답해.",
  "model": "flash",
  "pollIntervalMs": 2000,
  "timeoutMs": 600000
}
// → {
//   "jobId": "g-...",
//   "status": "completed" | "failed" | "timeout",
//   "elapsedMs": 45372,
//   "polls": 15,
//   "result": { "found": true, "available": true, "output": "2", "raw": "..." }
// }
```

- 내부에서 `background: true`를 강제하고 `gemini_task` → `gemini_status` 루프 → `gemini_result`를 한 번에 수행한다.
- `timeoutMs` 초과 시 `status: "timeout"`, `result: null`. job은 취소하지 않으므로 나중에 같은 `jobId`로 `gemini_result` 재수집 가능.
- `status: "failed"`는 companion이 실패로 전이한 경우이며, 이때도 `gemini_result`를 한 번 더 호출해 에러 상세를 `result`에 담는다.

## 제한

- **Auto-poll 또는 3-step**: 기본은 `gemini_run` 한 번으로 완결된다. 중간 진행 상태가 필요할 때만 `task → status → result` 3-step을 사용한다.
- **Result output 파싱**: gemini-companion은 plain text stdout을 뱉는다. `gemini-exec.mjs`의 `runCompanion`은 JSON.parse를 시도하지 않고 항상 `{ raw: stdout }`을 돌려주며, `parseResultOutput`이 `output` 필드를 `raw.trim()`으로 채운다. (초기 버전에서 JSON.parse가 "2" 같은 숫자 응답을 삼키던 버그는 Phase 4에서 수정됨.)
- **Skill 플러그인과 job store 공유**: `Skill("gemini:rescue", ...)`와 `gemini_task`는 동일 companion job 디렉토리를 사용한다. 양쪽에서 등록한 job을 교차 조회 가능.
- **Companion worker stall 가능성**: gemini-companion 자체가 API rate-limit 또는 네트워크 이슈로 특정 job이 running 상태에서 고정될 수 있다. 이 경우 `gemini_cancel`로 중단하거나 프로세스 재시작이 필요하다. MCP 서버는 이를 감지하지 않는다.
- **플러그인 경로 의존**: `~/.claude/plugins/cache/claude-gemini-plugin/gemini/*/scripts/gemini-companion.mjs` 필수.
