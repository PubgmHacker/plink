// webpayGrant.unit.test.ts — юнит-тесты идемпотентности веб-гранта Plink+
// (без БД: prisma замокан).
// Аудит 26.07.2026 P2: выдача была check-then-act (findFirst до транзакции),
// поэтому две пересекающиеся доставки payment.succeeded от ЮKassa выдавали
// премиум дважды. После миграции 20260726120500_billing_idempotency на
// Subscription.originalTransactionId есть @unique, и проверки «уже выдано?»
// больше нет вовсе: повтор отбивает база (P2002), а откат происходит ДО
// user.update — значит срок подписки второй раз не продлевается.

import { describe, it, expect, vi, beforeEach } from 'vitest';

const { prismaMock, logAuditMock } = vi.hoisted(() => ({
  prismaMock: { $transaction: vi.fn() },
  logAuditMock: vi.fn(),
}));

vi.mock('../../config/db.js', () => ({ prisma: prismaMock }));
vi.mock('../../utils/audit.js', () => ({ logAudit: logAuditMock }));

import { grantWebPremium } from '../../routes/webpay.js';

const P2002 = () => Object.assign(new Error('Unique constraint failed'), { code: 'P2002' });

/// Фейковый tx-клиент. duplicate=true — база отбивает вставку уникальным
/// ограничением (повторная доставка вебхука); granted=true — строка уже есть
/// (повтор на базе, где уникальный индекс ещё не создан миграцией).
function makeTx(opts: {
  duplicate?: boolean;
  granted?: boolean;
  user?: { isPremium: boolean; premiumUntil: Date | null };
} = {}) {
  return {
    subscription: {
      findFirst: vi.fn().mockResolvedValue(opts.granted ? { id: 'sub-1' } : null),
      create: opts.duplicate
        ? vi.fn().mockRejectedValue(P2002())
        : vi.fn().mockResolvedValue({}),
    },
    user: {
      findUnique: vi.fn().mockResolvedValue(opts.user ?? { isPremium: false, premiumUntil: null }),
      update: vi.fn().mockResolvedValue({}),
    },
  };
}

/// $transaction прокидывает ошибку из тела наружу — как настоящий Prisma.
function runTx(tx: any) {
  return async (fn: any) => fn(tx);
}

beforeEach(() => {
  prismaMock.$transaction.mockReset();
  logAuditMock.mockReset();
});

describe('grantWebPremium', () => {
  it('выдаёт премиум внутри Serializable-транзакции', async () => {
    const tx = makeTx();
    prismaMock.$transaction.mockImplementation(runTx(tx));

    const result = await grantWebPremium('user-1', '1m', 'pay-1');

    expect(result).toBe('granted');
    expect(tx.subscription.create).toHaveBeenCalledTimes(1);
    expect(tx.subscription.create.mock.calls[0][0].data.originalTransactionId).toBe('yookassa:pay-1');
    expect(tx.user.update).toHaveBeenCalledTimes(1);
    expect(prismaMock.$transaction.mock.calls[0][1]).toEqual({ isolationLevel: 'Serializable' });
    expect(logAuditMock).toHaveBeenCalledTimes(1);
  });

  it('продление копится от конца текущей подписки (30 + 90 = 120 дней)', async () => {
    const now = Date.now();
    const until30 = new Date(now + 30 * 24 * 3600 * 1000);
    const tx = makeTx({ user: { isPremium: true, premiumUntil: until30 } });
    prismaMock.$transaction.mockImplementation(runTx(tx));

    await grantWebPremium('user-1', '3m', 'pay-2');

    const granted: Date = tx.user.update.mock.calls[0][0].data.premiumUntil;
    const days = Math.round((granted.getTime() - now) / (24 * 3600 * 1000));
    expect(days).toBe(120);
    // Подписка и пользователь получают один и тот же срок.
    expect(tx.subscription.create.mock.calls[0][0].data.expiresAt).toEqual(granted);
  });

  it('повторная доставка того же платежа не продлевает подписку (P2002 из create)', async () => {
    const tx = makeTx({ duplicate: true, user: { isPremium: true, premiumUntil: new Date(Date.now() + 1e9) } });
    prismaMock.$transaction.mockImplementation(runTx(tx));

    const result = await grantWebPremium('user-1', '1m', 'pay-1');

    expect(result).toBe('duplicate');
    // Регресс: премиум не должен продлеваться повторно — вставка падает ДО user.update.
    expect(tx.user.update).not.toHaveBeenCalled();
    expect(logAuditMock).not.toHaveBeenCalled();
  });

  it('повтор отбивается и БЕЗ уникального индекса (база без миграции)', async () => {
    // Регресс: если код выкачен раньше prisma migrate deploy, индекса нет и
    // create прошёл бы молча — премиум продлился бы второй раз без единой
    // ошибки в логах. Проверка внутри транзакции обязана это поймать.
    const tx = makeTx({ granted: true, user: { isPremium: true, premiumUntil: new Date(Date.now() + 1e9) } });
    prismaMock.$transaction.mockImplementation(runTx(tx));

    const result = await grantWebPremium('user-1', '1m', 'pay-1');

    expect(result).toBe('duplicate');
    expect(tx.subscription.findFirst.mock.calls[0][0].where.originalTransactionId).toBe('yookassa:pay-1');
    expect(tx.subscription.create).not.toHaveBeenCalled();
    expect(tx.user.update).not.toHaveBeenCalled();
    expect(logAuditMock).not.toHaveBeenCalled();
  });

  it('нарушение уникальности (гонка разрешена базой) — это дубликат, а не 500', async () => {
    prismaMock.$transaction.mockRejectedValue(P2002());

    await expect(grantWebPremium('user-1', '1m', 'pay-1')).resolves.toBe('duplicate');
    expect(logAuditMock).not.toHaveBeenCalled();
  });

  it('прочие ошибки БД пробрасываются (вебхук ответит 5xx и ЮKassa повторит)', async () => {
    prismaMock.$transaction.mockRejectedValue(Object.assign(new Error('serialization'), { code: 'P2034' }));

    await expect(grantWebPremium('user-1', '1m', 'pay-1')).rejects.toThrow('serialization');
  });
});
