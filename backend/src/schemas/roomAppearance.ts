// src/schemas/roomAppearance.ts — GPT-5.6 §7
import { z } from 'zod';

export const roomAppearanceSchema = z.object({
  version: z.literal(1),
  themeId: z.enum(['electric-blue', 'cinema-ember', 'violet-horizon', 'plink-teal', 'magenta-bloom']),
  motion: z.enum(['system', 'static']).default('system'),
});

export type RoomAppearance = z.infer<typeof roomAppearanceSchema>;

export const PREMIUM_THEME_IDS = new Set(['cinema-ember', 'violet-horizon', 'magenta-bloom']);
