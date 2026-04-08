#!/usr/bin/env node

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListResourcesRequestSchema,
  ListResourceTemplatesRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

import { geminiCancel, geminiResult, geminiRun, geminiStatus, geminiTask } from './gemini-exec.mjs';
import {
  geminiCancelInput,
  geminiResultInput,
  geminiRunInput,
  geminiStatusInput,
  geminiTaskInput
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

const server = new McpServer({ name: 'gemini-mcp', version: '0.1.0' });

server.registerTool(
  'gemini_task',
  {
    title: 'Gemini 작업 enqueue',
    description: 'gemini-companion task를 호출해 Gemini 작업을 실행하거나 큐에 등록합니다.',
    inputSchema: geminiTaskInput
  },
  async (input) => {
    try {
      const result = await geminiTask(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'gemini_run',
  {
    title: 'Gemini 작업 실행+폴링',
    description: 'Gemini 작업을 항상 백그라운드로 등록한 뒤 완료/실패까지 폴링하고 최종 결과를 수집합니다.',
    inputSchema: geminiRunInput
  },
  async (input) => {
    try {
      const result = await geminiRun(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'gemini_status',
  {
    title: 'job 상태 조회',
    description: '현재 Gemini job 상태 또는 최근 job 목록을 조회합니다.',
    inputSchema: geminiStatusInput
  },
  async (input) => {
    try {
      const result = await geminiStatus(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'gemini_result',
  {
    title: 'job 결과 수집',
    description: '완료된 Gemini job의 저장된 결과를 조회합니다.',
    inputSchema: geminiResultInput
  },
  async (input) => {
    try {
      const result = await geminiResult(input);
      return successResponse(result);
    } catch (error) {
      return errorResponse(error);
    }
  }
);

server.registerTool(
  'gemini_cancel',
  {
    title: 'job 취소',
    description: '실행 중이거나 대기 중인 Gemini job을 취소합니다.',
    inputSchema: geminiCancelInput
  },
  async (input) => {
    try {
      const result = await geminiCancel(input);
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
