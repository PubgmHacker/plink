// webpayStatus.unit.test.ts — статус, который читает iOS-приложение
// (GET /api/webpay/status, потребитель — PlinkWebPlansLoader).
//
// Зачем тест: App Review 3.1.1 запрещает уводить пользователя из iOS-приложения
// на веб-оплату /plus. Единственный источник правды про этот режим — env-флаг
// APP_STORE_COMPLIANT, но до сих пор он жил только в строке /health и НЕ управлял
// ничем. Эндпоинт, который приложение реально читает, обязан его нести, чтобы
// флаг управлял поведением клиента, а не логом. Здесь это закреплено:
//   1. эндпоинт отдаёт планы (1m/3m/12m) и признак enabled;
//   2. поле appStoreCompliant присутствует и по умолчанию true (fail-safe);
//   3. переключение флага переключает поле (флаг реально управляет контрактом);
//   4. enabled не завязан на флаг — он про наличие ключей ЮKassa.
//
// prisma и audit подтягиваются импортом webpay.ts, но /webpay/status их не трогает.
// Конфиг НЕ мокаем: webpay.ts читает process.env.APP_STORE_COMPLIANT напрямую,
// поэтому режим переключаем через окружение (и восстанавливаем в afterEach).

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

const { prismaMock, logAuditMock } = vi.hoisted(() => ({
  prismaMock: {},
  logAuditMock: vi.fn(),
}));

vi.mock('../../config/db.js', () => ({ prisma: prismaMock }));
vi.mock('../../utils/audit.js', () => ({ logAudit: logAuditMock }));

import webpayRoutes from '../../routes/webpay.js';

async function status(): Promise<{ statusCode: number; body: Record<string, unknown> }> {
  const app: FastifyInstance = Fastify();
  await app.register(webpayRoutes, { prefix: '/api' });
  await app.ready();
  try {
    const res = await app.inject({ method: 'GET', url: '/api/webpay/status' });
    return { statusCode: res.statusCode, body: res.json() as Record<string, unknown> };
  } finally {
    await app.close();
  }
}

const PREV = process.env.APP_STORE_COMPLIANT;
beforeEach(() => {
  delete process.env.APP_STORE_COMPLIANT; // по умолчанию — compliant (fail-safe)
});
afterEach(() => {
  if (PREV === undefined) delete process.env.APP_STORE_COMPLIANT;
  else process.env.APP_STORE_COMPLIANT = PREV;
});

describe('/api/webpay/status', () => {
  it('отдаёт планы 1m/3m/12m и признак enabled', async () => {
    const { statusCode, body } = await status();
    expect(statusCode).toBe(200);
    expect(body).toHaveProperty('enabled');
    expect(body).toHaveProperty('plans');
    const plans = body.plans as Record<string, unknown>;
    for (const id of ['1m', '3m', '12m']) {
      expect(plans).toHaveProperty(id);
    }
  });

  it('несёт appStoreCompliant, и по умолчанию (флаг не задан) он true', async () => {
    const { body } = await status();
    expect(body.appStoreCompliant).toBe(true);
  });

  it('флаг реально управляет полем: APP_STORE_COMPLIANT=false → false', async () => {
    process.env.APP_STORE_COMPLIANT = 'false';
    const { body } = await status();
    expect(body.appStoreCompliant).toBe(false);
    // enabled — про наличие ключей ЮKassa, а не про флаг; поле остаётся.
    expect(body).toHaveProperty('enabled');
  });

  it('любое иное значение флага трактуется как compliant (fail-safe)', async () => {
    process.env.APP_STORE_COMPLIANT = 'true';
    const { body } = await status();
    expect(body.appStoreCompliant).toBe(true);
  });
});
