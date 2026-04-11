#!/usr/bin/env node

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListResourcesRequestSchema,
  ListResourceTemplatesRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

import { getMemoryStore } from './memory-store.mjs';
import {
  memoryStoreInput,
  memoryRecallInput,
  memoryListInput,
  memoryDeleteInput,
  memoryUpdateInput
} from './schema.mjs';

function ok(result) {
  return {
    content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
    structuredContent: result
  };
}

function err(error) {
  return {
    content: [{ type: 'text', text: `Error: ${error.message}` }],
    isError: true
  };
}

const server = new McpServer({ name: 'memory-mcp', version: '0.1.0' });

// ── memory_store ──────────────────────────────────────────────────────────────
server.registerTool(
  'memory_store',
  {
    title: '메모리 저장',
    description:
      '에이전트 메모리를 저장합니다. type으로 분류하고 tags로 검색 편의를 높이세요. ' +
      '저장 후 recall로 다시 찾을 수 있습니다.',
    inputSchema: memoryStoreInput
  },
  async (input) => {
    try {
      const store = getMemoryStore();
      const result = store.store(input);
      return ok({ status: 'stored', ...result });
    } catch (e) {
      return err(e);
    }
  }
);

// ── memory_recall ─────────────────────────────────────────────────────────────
server.registerTool(
  'memory_recall',
  {
    title: '메모리 검색',
    description:
      '쿼리와 관련된 메모리를 전문검색(FTS5)으로 찾습니다. ' +
      '한국어/영어 모두 지원. type 필터로 범위를 좁힐 수 있습니다.',
    inputSchema: memoryRecallInput
  },
  async (input) => {
    try {
      const store = getMemoryStore();
      const results = store.recall(input);
      return ok({ count: results.length, results });
    } catch (e) {
      return err(e);
    }
  }
);

// ── memory_list ───────────────────────────────────────────────────────────────
server.registerTool(
  'memory_list',
  {
    title: '메모리 목록 조회',
    description:
      '최근 저장된 메모리를 시간 역순으로 나열합니다. ' +
      'type 또는 source로 필터 가능. 검색보다 브라우징에 적합.',
    inputSchema: memoryListInput
  },
  async (input) => {
    try {
      const store = getMemoryStore();
      const results = store.list(input);
      return ok({ count: results.length, results });
    } catch (e) {
      return err(e);
    }
  }
);

// ── memory_delete ─────────────────────────────────────────────────────────────
server.registerTool(
  'memory_delete',
  {
    title: '메모리 삭제',
    description: 'ID로 특정 메모리를 삭제합니다. 복구 불가.',
    inputSchema: memoryDeleteInput
  },
  async (input) => {
    try {
      const store = getMemoryStore();
      const result = store.delete(input);
      return ok({ status: 'deleted', ...result });
    } catch (e) {
      return err(e);
    }
  }
);

// ── memory_update ─────────────────────────────────────────────────────────────
server.registerTool(
  'memory_update',
  {
    title: '메모리 업데이트',
    description: '기존 메모리의 content 또는 tags를 수정합니다. id 필수.',
    inputSchema: memoryUpdateInput
  },
  async (input) => {
    try {
      const store = getMemoryStore();
      const result = store.update(input);
      return ok({ status: 'updated', ...result });
    } catch (e) {
      return err(e);
    }
  }
);

// ── memory_stats ──────────────────────────────────────────────────────────────
server.registerTool(
  'memory_stats',
  {
    title: '메모리 통계',
    description: '저장된 메모리 수, 타입별 분포를 반환합니다.',
    inputSchema: {}
  },
  async () => {
    try {
      const store = getMemoryStore();
      const result = store.stats();
      return ok(result);
    } catch (e) {
      return err(e);
    }
  }
);

// Empty resource handlers (suppress -32601 warnings from MCP clients)
server.server.registerCapabilities({ resources: {} });
server.server.setRequestHandler(ListResourcesRequestSchema, async () => ({ resources: [] }));
server.server.setRequestHandler(ListResourceTemplatesRequestSchema, async () => ({
  resourceTemplates: []
}));

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection:', reason);
});

const transport = new StdioServerTransport();
await server.connect(transport);
