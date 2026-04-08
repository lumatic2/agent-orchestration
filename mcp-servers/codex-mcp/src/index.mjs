#!/usr/bin/env node

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListResourcesRequestSchema,
  ListResourceTemplatesRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

import { codexCancel, codexResult, codexRun, codexStatus, codexTask } from './codex-exec.mjs';
import {
  codexCancelInput,
  codexResultInput,
  codexRunInput,
  codexStatusInput,
  codexTaskInput
} from './schema.mjs';

function successResponse(result) {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(result, null, 2)
      }
    ],
    structuredContent: result
  };
}

function errorResponse(error) {
  return {
    content: [
      {
        type: 'text',
        text: `Error: ${error.message}`
      }
    ],
    isError: true
  };
}

const server = new McpServer({ name: 'codex-mcp', version: '0.1.0' });

server.registerTool(
  'codex_task',
  {
    title: 'Codex 작업 enqueue',
    description: 'codex-companion task --background를 호출해 Codex 작업을 큐에 등록합니다.',
    inputSchema: codexTaskInput
  },
  async (input) => {
    try {
      const result = await codexTask(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'codex_run',
  {
    title: 'Codex 작업 실행+폴링',
    description: 'Codex 작업을 백그라운드로 등록한 뒤 완료/실패까지 폴링하고 최종 결과를 수집합니다.',
    inputSchema: codexRunInput
  },
  async (input) => {
    try {
      const result = await codexRun(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'codex_status',
  {
    title: 'job 상태 조회',
    description: '현재 job 상태 또는 전체 상태 스냅샷을 조회합니다.',
    inputSchema: codexStatusInput
  },
  async (input) => {
    try {
      const result = await codexStatus(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'codex_result',
  {
    title: 'job 결과 수집',
    description: '완료된 Codex job의 저장된 결과를 조회합니다.',
    inputSchema: codexResultInput
  },
  async (input) => {
    try {
      const result = await codexResult(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'codex_cancel',
  {
    title: 'job 취소',
    description: '실행 중이거나 대기 중인 Codex job을 취소합니다.',
    inputSchema: codexCancelInput
  },
  async (input) => {
    try {
      const result = await codexCancel(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

// Empty resources/list + resources/templates/list handlers so MCP clients
// (e.g. Codex CLI) that probe these methods at session start don't log
// "-32601 Method not found" warnings. This server intentionally exposes
// no resources; only tools.
server.server.registerCapabilities({ resources: {} });
server.server.setRequestHandler(ListResourcesRequestSchema, async () => ({ resources: [] }));
server.server.setRequestHandler(ListResourceTemplatesRequestSchema, async () => ({ resourceTemplates: [] }));

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection:', reason);
});

const transport = new StdioServerTransport();
await server.connect(transport);
