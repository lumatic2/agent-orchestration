import { z } from 'zod';

export const codexTaskInput = {
  prompt: z.string().describe('Codex에 줄 작업 지시'),
  write: z.boolean().optional().default(false).describe('workspace-write sandbox'),
  model: z.enum(['default', 'spark']).optional(),
  effort: z.enum(['low', 'medium', 'high']).optional(),
  resume: z.boolean().optional().default(false),
  fresh: z.boolean().optional().default(false),
  cwd: z.string().optional().describe('작업 디렉토리 절대 경로')
};

export const codexRunInput = {
  ...codexTaskInput,
  pollIntervalMs: z.number().int().positive().optional().default(2000),
  timeoutMs: z.number().int().positive().optional().default(600000)
};

export const codexStatusInput = {
  jobId: z.string().optional()
};

export const codexResultInput = {
  jobId: z.string()
};

export const codexCancelInput = {
  jobId: z.string()
};
