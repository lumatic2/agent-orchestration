import { z } from 'zod';

const MEMORY_TYPES = ['research', 'decision', 'code_pattern', 'fact', 'general'];

export const memoryStoreInput = {
  content: z.string().min(1).describe('저장할 내용. 나중에 검색할 때 쓰는 텍스트.'),
  type: z
    .enum(MEMORY_TYPES)
    .default('general')
    .describe(
      'research: 리서치 요약 | decision: 라우팅/설계 결정 근거 | code_pattern: 코드 패턴 | fact: 검증된 사실 | general: 기타'
    ),
  tags: z
    .array(z.string())
    .optional()
    .describe('검색 편의를 위한 태그 목록. 예: ["typescript", "routing", "bug"]'),
  source: z
    .string()
    .optional()
    .describe('저장한 에이전트 또는 세션 식별자. 예: "gemini", "claude", "deep-research-session-3"')
};

export const memoryRecallInput = {
  query: z.string().min(1).describe('검색 쿼리. 관련 메모리를 FTS로 검색한다.'),
  type: z
    .enum(MEMORY_TYPES)
    .optional()
    .describe('특정 타입으로 필터. 생략하면 전체 타입 검색.'),
  limit: z
    .number()
    .int()
    .min(1)
    .max(50)
    .default(10)
    .describe('반환할 최대 결과 수. 기본 10, 최대 50.')
};

export const memoryListInput = {
  type: z.enum(MEMORY_TYPES).optional().describe('타입 필터. 생략하면 전체.'),
  limit: z
    .number()
    .int()
    .min(1)
    .max(100)
    .default(20)
    .describe('최근 N개 반환. 기본 20, 최대 100.'),
  source: z.string().optional().describe('특정 에이전트/세션의 메모리만 필터.')
};

export const memoryDeleteInput = {
  id: z.string().min(1).describe('삭제할 메모리 ID.')
};

export const memoryUpdateInput = {
  id: z.string().min(1).describe('업데이트할 메모리 ID.'),
  content: z.string().min(1).optional().describe('새 내용.'),
  tags: z.array(z.string()).optional().describe('새 태그 목록 (기존 태그 교체).')
};
