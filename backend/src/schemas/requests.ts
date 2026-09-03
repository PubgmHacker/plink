// src/schemas/requests.ts — zod-схемы входа для критичных маршрутов (P1 5.7).
//
// Схемы кодифицируют УЖЕ существующие проверки хендлеров (границы длин,
// форматы) и отсекают мусорные типы до бизнес-логики. Все объекты —
// .passthrough(): validateBody() подменяет request.body результатом parse,
// и строгая схема молча выкидывала бы поля, о которых знает хендлер,
// но не знает схема.

import { z } from 'zod';

// ─── auth ────────────────────────────────────────────────────────────────

export const signupBody = z
  .object({
    email: z.string().email().max(254),
    password: z.string().min(6).max(128),
    // Telegram-style: буква + 4-31 символ [A-Za-z0-9_] (см. auth.ts P0.5).
    username: z.string().regex(/^[A-Za-z][A-Za-z0-9_]{4,31}$/),
  })
  .passthrough();

export const signinBody = z
  .object({
    email: z.string().email().max(254),
    password: z.string().min(1).max(128),
  })
  .passthrough();

export const refreshBody = z
  .object({
    refreshToken: z.string().min(10).max(4096),
  })
  .passthrough();

export const adminVerifyBody = z
  .object({
    email: z.string().email().max(254),
    code: z.string().min(4).max(64),
  })
  .passthrough();

export const appleAuthBody = z
  .object({
    identityToken: z.string().min(20).max(16_384),
    fullName: z.string().max(120).nullish(),
  })
  .passthrough();

/** Anonymous web guest for /w/:code (install-free YouTube watch). */
export const guestAuthBody = z
  .object({
    roomCode: z.string().min(4).max(12).optional(),
  })
  .passthrough();

export const forgotPasswordBody = z
  .object({
    email: z.string().email().max(254),
  })
  .passthrough();

export const resetPasswordBody = z
  .object({
    email: z.string().email().max(254),
    code: z.string().regex(/^\d{6}$/),
    newPassword: z.string().min(6).max(128),
  })
  .passthrough();

// ─── billing ─────────────────────────────────────────────────────────────

export const billingVerifyBody = z
  .object({
    jws: z.string().min(10).max(200_000),
    productId: z.string().min(1).max(200),
    transactionId: z.string().max(200).optional(),
  })
  .passthrough();

// ─── rooms ───────────────────────────────────────────────────────────────

export const roomCreateBody = z
  .object({
    name: z.string().min(1).max(120),
    maxParticipants: z.coerce.number().int().min(2).max(50).optional(),
    // Полная валидация mediaItem — в сервисном слое; здесь только форма.
    mediaItem: z.object({}).passthrough().nullish(),
    privacy: z.string().max(24).optional(),
    password: z.string().max(72).nullish(),
    hostName: z.string().max(64).optional(),
  })
  .passthrough();

export const roomJoinBody = z
  .object({
    code: z.string().min(4).max(12),
    password: z.string().max(72).nullish(),
  })
  .passthrough();

// Порядок очереди: список id в желаемом порядке. Ограничение 50 совпадает с
// MAX_QUEUE в roomQueueStore — присылать больше бессмысленно.
export const roomQueueReorderBody = z
  .object({
    order: z.array(z.string().min(1).max(128)).min(1).max(50),
  })
  .passthrough();

// ─── messages ────────────────────────────────────────────────────────────

export const dmSendBody = z
  .object({
    receiverId: z.string().min(1).max(64),
    // 280 — лимит хендлера (инвайты не влезали в 150).
    content: z.string().min(1).max(280),
    replyToId: z.string().max(64).nullish(),
  })
  .passthrough();
