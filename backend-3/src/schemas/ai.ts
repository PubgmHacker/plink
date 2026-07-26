// src/schemas/ai.ts — GPT-5.6 §12
import { z } from 'zod';

export const aiRequestSchema = z.object({
  conversationId: z.string().uuid().optional(),
  message: z.string().trim().min(1).max(4000),
  context: z.object({ roomId: z.string().optional() }).strict(),
});

export type AIRequest = z.infer<typeof aiRequestSchema>;
