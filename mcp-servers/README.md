# mcp-servers

> agent-orchestration의 방향 2 구현체. Codex CLI와 Gemini CLI를 MCP(Model Context Protocol) 서버로 래핑해서 Claude Code, Cursor, Windsurf 등 모든 MCP 클라이언트에서 "에이전트를 도구로" 호출 가능하게 만든다.

배경과 설계 결정은 [`../docs/orchestration-roadmap.md`](../docs/orchestration-roadmap.md)와 [`../docs/mcp-servers.md`](../docs/mcp-servers.md) 참조.

## 구조

```
mcp-servers/
├── codex-mcp/   # Codex CLI → MCP 서버
└── gemini-mcp/  # Gemini CLI → MCP 서버
```

두 서버는 동일한 설계 원칙을 따른다:

1. **Thin shell-out 래퍼**: 기존 `codex-companion.mjs` / `gemini-companion.mjs`를 subprocess로 exec한다. 내부 로직을 재구현하지 않는다. 플러그인 업그레이드에 강한 격리 경계를 둔다.
2. **Enqueue + poll 패턴**: MCP 도구는 동기 응답이 기본이라 장시간 작업은 `*_task`(enqueue) → `*_status`(poll) → `*_result`(fetch) 3-step으로 분리해 노출한다.
3. **Stdio transport**: Claude Code/Cursor/Windsurf 모두 지원하는 가장 보편적인 트랜스포트.
4. **Node .mjs**: TypeScript 컴파일 단계 제거. codex-companion과 동일 런타임(Node) 사용.

## 도구 목록

### codex-mcp

| Tool | 목적 |
|---|---|
| `codex_task` | Codex 작업 enqueue. `prompt`, `write`, `model`, `effort`, `resume`/`fresh`, `cwd` 지원 |
| `codex_status` | job 상태 조회 (단일 또는 전체 목록) |
| `codex_result` | 완료된 job의 stdout/logs 회수 |
| `codex_cancel` | 실행 중 job 취소 |

### gemini-mcp

| Tool | 목적 |
|---|---|
| `gemini_task` | Gemini 작업 실행. `prompt`, `model`(flash/pro), `background` 지원 |
| `gemini_status` | job 상태 조회 |
| `gemini_result` | 완료된 job 출력 회수 |
| `gemini_cancel` | 실행 중 job 취소 |

## 등록

### Claude Code

```bash
claude mcp add codex-mcp -- node C:/Users/yusun/projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs
claude mcp add gemini-mcp -- node C:/Users/yusun/projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs
```

등록 후 Claude Code 재시작. `mcp__codex-mcp__codex_task` / `mcp__gemini-mcp__gemini_task` 형태로 도구 노출.

### Cursor / Windsurf / 기타 MCP 클라이언트

각 클라이언트의 MCP 설정 파일(예: Cursor `~/.cursor/mcp.json`)에 아래 형식으로 추가:

```json
{
  "mcpServers": {
    "codex-mcp": {
      "command": "node",
      "args": ["C:/Users/yusun/projects/agent-orchestration/mcp-servers/codex-mcp/src/index.mjs"]
    },
    "gemini-mcp": {
      "command": "node",
      "args": ["C:/Users/yusun/projects/agent-orchestration/mcp-servers/gemini-mcp/src/index.mjs"]
    }
  }
}
```

## 환경변수

| 변수 | 기본값 | 용도 |
|---|---|---|
| `CODEX_COMPANION_PATH` | auto-resolve (최신 `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`) | codex-companion 경로 override |
| `GEMINI_COMPANION_PATH` | `~/.claude/plugins/cache/claude-gemini-plugin/gemini/1.0.0/scripts/gemini-companion.mjs` | gemini-companion 경로 override |

플러그인 업그레이드 시 자동 해결. 테스트 환경에서 특정 버전을 고정하려면 env var로 override.

## 기존 Skill 플러그인과의 관계

`codex:rescue` / `gemini:rescue` Skill 플러그인은 **Claude Code 전용 shortcut**으로 유지한다. 이 MCP 서버는 **다중 클라이언트 지원 + 에이전트 간 체이닝**이 목적. 한동안 공존하며 실사용 데이터를 바탕으로 장기 운명을 결정한다. 자세한 정책은 [`../docs/mcp-servers.md`](../docs/mcp-servers.md) 참조.
