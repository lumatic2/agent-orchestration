import { z } from 'zod';

export const geminiTaskInput = {
  prompt: z.string().describe('Gemini에 줄 질문/작업'),
  model: z.enum(['flash', 'pro']).optional().describe('모델 선택(flash=빠름, pro=심층)'),
  background: z.boolean().optional().default(true).describe('백그라운드 실행 여부')
};

export const geminiRunInput = {
  ...geminiTaskInput,
  pollIntervalMs: z.number().int().positive().optional().default(2000),
  timeoutMs: z.number().int().positive().optional().default(600000)
};

export const geminiStatusInput = {
  jobId: z.string().optional()
};

export const geminiResultInput = {
  jobId: z.string()
};

export const geminiCancelInput = {
  jobId: z.string()
};
