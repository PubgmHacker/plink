// billingIdempotency.unit.test.ts — idempotency of Apple purchases
// (no database: prisma and signature verification are mocked).
//
// Invariants exercised here — the supporting schema lives in migration
// 20260726120500_billing_idempotency:
//   1. verify keys the subscription upsert on originalTransactionId (@unique),
//      not on the primary key — otherwise the update branch is dead and every
//      verify/renew spawns a second active subscription.
//   2. Server Notifications V2 webhooks are deduplicated by notificationUUID
//      through the AppleNotification table: the claim row is inserted BEFORE
//      processing, a race is resolved by the primary key (P2002), and a repeat
//      short-circuits with 200.
//   3. A stale DID_RENEW delivered after REFUND/REVOKE does not restore
//      premium for a revoked user.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import Fastify from 'fastify';

const { prismaMock, logAuditMock, joseMock } = vi.hoisted(() => ({
  prismaMock: {
    $transaction: vi.fn(),
    user: { findUnique: vi.fn(), update: vi.fn() },
    subscription: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      upsert: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      count: vi.fn(),
    },
    transactionRecord: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      upsert: vi.fn(),
      updateMany: vi.fn(),
    },
    appleNotification: { create: vi.fn(), update: vi.fn(), delete: vi.fn(), findFirst: vi.fn() },
    auditLog: { create: vi.fn() },
  },
  logAuditMock: vi.fn(),
  joseMock: {
    verifySignedTransaction: vi.fn(),
    verifyNotificationV2: vi.fn(),
  },
}));

vi.mock('../../config/db.js', () => ({ prisma: prismaMock }));
vi.mock('../../utils/audit.js', () => ({ logAudit: logAuditMock, AuditActions: {} }));
vi.mock('../../utils/jose-config.js', () => ({ JoseConfig: joseMock }));

import billingRoutes from '../../routes/billing.js';

const USER_ID = 'user-1';
const ORIG_TX = 'orig-tx-1';
const P2002 = () => Object.assign(new Error('Unique constraint failed'), { code: 'P2002' });

/// JWS-заглушка: подпись проверяет замоканный JoseConfig, поэтому содержимое
/// не важно — важно лишь, что ключи идемпотентности берутся из ЕГО ответа.
const FAKE_JWS = 'header.payload.signature';

async function buildApp() {
  const app = Fastify();
  app.decorate('authenticate', async (request: any) => {
    request.user = { id: USER_ID };
  });
  await app.register(billingRoutes);
  await app.ready();
  return app;
}

/// Все методы prisma возвращают «пусто», $transaction прокидывает тот же клиент.
function resetPrisma() {
  for (const model of Object.values(prismaMock) as any[]) {
    if (typeof model === 'function') {
      model.mockReset();
      continue;
    }
    for (const fn of Object.values(model) as any[]) {
      fn.mockReset();
      fn.mockResolvedValue(null);
    }
  }
  prismaMock.$transaction.mockImplementation(async (fn: any) => fn(prismaMock));
  prismaMock.subscription.count.mockResolvedValue(0);
  prismaMock.user.update.mockResolvedValue({});
}

beforeEach(() => {
  resetPrisma();
  logAuditMock.mockReset();
  joseMock.verifySignedTransaction.mockReset();
  joseMock.verifyNotificationV2.mockReset();
});

describe('POST /billing/verify — идемпотентность подписки', () => {
  const expiresAt = Date.now() + 30 * 24 * 3600 * 1000;

  function mockVerifiedTransaction() {
    joseMock.verifySignedTransaction.mockReturnValue({
      originalTransactionId: ORIG_TX,
      transactionId: 'tx-1',
      environment: 'Production',
      expiresAt,
      revocationDate: undefined,
      productId: 'plink.plus.1m',
      bundleId: 'com.syncwatch.plink',
      signedDate: Date.now(),
    });
  }

  it('upsert ключуется по originalTransactionId, ветка create заполняет всё, что и update', async () => {
    mockVerifiedTransaction();
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/verify',
      payload: { jws: FAKE_JWS, productId: 'plink.plus.1m' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.subscription.upsert).toHaveBeenCalledTimes(1);
    const call = prismaMock.subscription.upsert.mock.calls[0][0];
    // Регресс: ключ — реально уникальное поле, иначе ветка update мертва.
    expect(call.where).toEqual({ originalTransactionId: ORIG_TX });
    // Ветка create обязана заполнять всё, что заполняла ветка update.
    for (const key of Object.keys(call.update)) {
      expect(call.create).toHaveProperty(key);
    }
    expect(call.create.userID).toBe(USER_ID);
    expect(call.create.isActive).toBe(true);
    expect(call.create.revokedAt).toBeNull();

    await app.close();
  });

  it('повторный verify с тем же originalTransactionId не плодит вторую активную строку', async () => {
    mockVerifiedTransaction();
    const app = await buildApp();
    const payload = { jws: FAKE_JWS, productId: 'plink.plus.1m' };

    await app.inject({ method: 'POST', url: '/billing/verify', payload });
    // Второй заход: строка уже есть и принадлежит тому же пользователю.
    prismaMock.subscription.findUnique.mockResolvedValue({ userID: USER_ID });
    const res = await app.inject({ method: 'POST', url: '/billing/verify', payload });

    expect(res.statusCode).toBe(200);
    // Слепого create нет вовсе — только upsert по одному и тому же ключу.
    expect(prismaMock.subscription.create).not.toHaveBeenCalled();
    const keys = prismaMock.subscription.upsert.mock.calls.map((c: any[]) => c[0].where);
    expect(keys).toEqual([{ originalTransactionId: ORIG_TX }, { originalTransactionId: ORIG_TX }]);
    // Гашение прочих активных подписок исключает каноническую строку по тому же
    // ключу и не трогает комплиментарные (originalTransactionId = NULL).
    const deactivate = prismaMock.subscription.updateMany.mock.calls[0][0].where;
    expect(deactivate.NOT).toEqual({ originalTransactionId: ORIG_TX });
    expect(deactivate.originalTransactionId).toEqual({ not: null });

    await app.close();
  });

  it('ключ идемпотентности берётся из проверенного JWS, а не из тела запроса', async () => {
    mockVerifiedTransaction();
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/verify',
      // Тело врёт про transactionId — сервер обязан отказать, а не подставить его.
      payload: { jws: FAKE_JWS, productId: 'plink.plus.1m', transactionId: 'forged-tx' },
    });

    expect(res.statusCode).toBe(400);
    expect(prismaMock.subscription.upsert).not.toHaveBeenCalled();

    await app.close();
  });

  it('JWS без идентификаторов транзакции отвергается (пустой ключ не занимает строку)', async () => {
    // verifySignedTransaction отдаёт '' , если в payload нет ни
    // originalTransactionId, ни transactionId. С @unique такая строка стала бы
    // глобальной: следующий пользователь получал бы 403 ownership_mismatch.
    joseMock.verifySignedTransaction.mockReturnValue({
      originalTransactionId: '',
      transactionId: undefined,
      environment: 'Production',
      expiresAt,
      productId: 'plink.plus.1m',
      bundleId: 'com.syncwatch.plink',
      signedDate: Date.now(),
    });
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/verify',
      payload: { jws: FAKE_JWS, productId: 'plink.plus.1m' },
    });

    expect(res.statusCode).toBe(400);
    expect(prismaMock.subscription.upsert).not.toHaveBeenCalled();
    expect(prismaMock.subscription.findUnique).not.toHaveBeenCalled();

    await app.close();
  });

  it('гонка двух параллельных verify (P2002) сходится, а не отдаёт 500', async () => {
    mockVerifiedTransaction();
    // Первая попытка проигрывает уникальному индексу, вторая уходит в update.
    prismaMock.$transaction
      .mockRejectedValueOnce(
        Object.assign(new Error('Unique constraint failed'), { code: 'P2002' }),
      )
      .mockImplementationOnce(async (fn: any) => fn(prismaMock));
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/verify',
      payload: { jws: FAKE_JWS, productId: 'plink.plus.1m' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.$transaction).toHaveBeenCalledTimes(2);

    await app.close();
  });
});

describe('POST /billing/webhooks/apple — дедупликация и приоритет по времени', () => {
  const NOTIF_UUID = 'notif-uuid-1';

  function mockNotification(
    type: string,
    opts: { signedDate?: number; expiresAt?: number; revocationDate?: number } = {},
  ) {
    joseMock.verifyNotificationV2.mockReturnValue({
      notificationType: type,
      notificationUUID: NOTIF_UUID,
      signedDate: opts.signedDate ?? Date.now(),
      data: { signedTransactionInfo: 'tx.jws.sig' },
    });
    joseMock.verifySignedTransaction.mockReturnValue({
      originalTransactionId: ORIG_TX,
      transactionId: 'tx-1',
      environment: 'Production',
      productId: 'plink.plus.1m',
      expiresAt: opts.expiresAt ?? Date.now() + 30 * 24 * 3600 * 1000,
      revocationDate: opts.revocationDate,
      signedDate: opts.signedDate ?? Date.now(),
    });
    prismaMock.subscription.findUnique.mockResolvedValue({
      userID: USER_ID,
      id: ORIG_TX,
      revokedAt: null,
      expiresAt: new Date(0),
    });
  }

  /// Мок appleNotification.findFirst, повторяющий семантику БД: фильтры
  /// notificationType/signedDate/NOT применяются РЕАЛЬНО. Без этого тест «более
  /// свежее уведомление» проходил бы при любом запросе — в том числе без
  /// фильтра по типу, из-за которого безобидный DID_CHANGE_RENEWAL_PREF
  /// отменял продление премиума.
  function mockKnownNotifications(
    rows: Array<{ notificationUUID: string; notificationType: string; signedDate: Date }>,
  ) {
    prismaMock.appleNotification.findFirst.mockImplementation(async (args: any) => {
      const types: string[] | null = args?.where?.notificationType?.in ?? null;
      const after: Date | undefined = args?.where?.signedDate?.gt;
      const excluded: string | undefined = args?.where?.NOT?.notificationUUID;
      const found = rows.find(
        (r) =>
          (types === null || types.includes(r.notificationType)) &&
          (!after || r.signedDate.getTime() > after.getTime()) &&
          r.notificationUUID !== excluded,
      );
      return found ?? null;
    });
  }

  it('одно и то же notificationUUID применяется ровно один раз', async () => {
    mockNotification('DID_RENEW');
    prismaMock.appleNotification.create.mockResolvedValueOnce({});
    const app = await buildApp();

    const first = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ processed: true });
    expect(prismaMock.subscription.updateMany).toHaveBeenCalledTimes(1);
    expect(prismaMock.appleNotification.create.mock.calls[0][0].data.notificationUUID).toBe(
      NOTIF_UUID,
    );

    // Повторная доставка: заявку отбивает первичный ключ.
    prismaMock.appleNotification.create.mockRejectedValueOnce(P2002());
    const second = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(second.statusCode).toBe(200);
    expect(second.json()).toEqual({ processed: false, reason: 'duplicate_notification' });
    // Эффект второй раз не применялся.
    expect(prismaMock.subscription.updateMany).toHaveBeenCalledTimes(1);
    expect(prismaMock.user.update).toHaveBeenCalledTimes(1);

    await app.close();
  });

  it('устаревший DID_RENEW после REFUND не возвращает премиум', async () => {
    const renewSignedAt = Date.now() - 3 * 3600 * 1000;
    mockNotification('DID_RENEW', { signedDate: renewSignedAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    // Возврат подписан ПОЗЖЕ продления (Apple прислал события не по порядку).
    prismaMock.subscription.findUnique.mockResolvedValue({
      userID: USER_ID,
      id: ORIG_TX,
      revokedAt: new Date(Date.now() - 3600 * 1000),
      expiresAt: new Date(0),
    });
    prismaMock.transactionRecord.findFirst.mockResolvedValue({
      revocationDate: new Date(Date.now() - 3600 * 1000),
    });
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    // Премиум НЕ включается обратно.
    expect(prismaMock.user.update).not.toHaveBeenCalled();
    const data = prismaMock.subscription.updateMany.mock.calls[0][0].data;
    expect(data.isActive).toBeUndefined();
    expect(data.revokedAt).toBeUndefined();
    expect(
      logAuditMock.mock.calls.some(
        (c: any[]) => c[0].action === 'billing.webhook.renewal_after_revocation',
      ),
    ).toBe(true);

    await app.close();
  });

  it('продление, обогнанное более свежим ГАШЕНИЕМ, не включает премиум', async () => {
    const renewSignedAt = Date.now() - 3 * 3600 * 1000;
    mockNotification('DID_RENEW', { signedDate: renewSignedAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    // По этой же подписке уже обработано истечение, подписанное позже.
    mockKnownNotifications([
      {
        notificationUUID: 'notif-uuid-2',
        notificationType: 'SUBSCRIPTION_EXPIRED',
        signedDate: new Date(Date.now() - 3600 * 1000),
      },
    ]);
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.user.update).not.toHaveBeenCalled();
    expect(prismaMock.subscription.updateMany.mock.calls[0][0].data.isActive).toBeUndefined();

    await app.close();
  });

  it('легитимный DID_RENEW ВКЛЮЧАЕТ премиум (положительный путь)', async () => {
    // Регресс на «глушилку»: все проверки приоритета по времени требовали
    // ОТСУТСТВИЯ эффекта, поэтому любое ужесточение условия проходило сьют,
    // хотя премиум переставал включаться у всех платящих.
    const expiresAt = Date.now() + 30 * 24 * 3600 * 1000;
    mockNotification('DID_RENEW', { expiresAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    mockKnownNotifications([]);
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.subscription.updateMany.mock.calls[0][0].data.isActive).toBe(true);
    expect(prismaMock.user.update).toHaveBeenCalledWith({
      where: { id: USER_ID },
      data: { isPremium: true, premiumUntil: new Date(expiresAt) },
    });

    await app.close();
  });

  it('нерелевантное уведомление (DID_CHANGE_RENEWAL_PREF) не отменяет продление', async () => {
    // Регресс: заявка пишется на ЛЮБУЮ доставку, поэтому смена тарифа,
    // подписанная на секунду позже продления, выключала реактивацию —
    // User.premiumUntil не продлевался, и премиум гас у оплатившего.
    const renewSignedAt = Date.now() - 3 * 3600 * 1000;
    const expiresAt = Date.now() + 30 * 24 * 3600 * 1000;
    mockNotification('DID_RENEW', { signedDate: renewSignedAt, expiresAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    mockKnownNotifications([
      {
        notificationUUID: 'notif-uuid-3',
        notificationType: 'DID_CHANGE_RENEWAL_PREF',
        signedDate: new Date(renewSignedAt + 1000),
      },
    ]);
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.subscription.updateMany.mock.calls[0][0].data.isActive).toBe(true);
    expect(prismaMock.user.update).toHaveBeenCalledWith({
      where: { id: USER_ID },
      data: { isPremium: true, premiumUntil: new Date(expiresAt) },
    });

    await app.close();
  });

  it('устаревший REFUND после более свежего продления не отбирает премиум', async () => {
    // Обратная гонка: период N возвращён, период N+1 уже оплачен и включён,
    // REFUND за N доставлен с задержкой. Раньше он гасил подписку и снимал
    // премиум с оплаченного периода.
    const refundSignedAt = Date.now() - 3 * 3600 * 1000;
    mockNotification('REFUND', { signedDate: refundSignedAt, revocationDate: refundSignedAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    mockKnownNotifications([
      {
        notificationUUID: 'notif-uuid-4',
        notificationType: 'DID_RENEW',
        signedDate: new Date(refundSignedAt + 3600 * 1000),
      },
    ]);
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    // Подписка не гасится, премиум у пользователя не снимается.
    expect(prismaMock.subscription.updateMany).not.toHaveBeenCalled();
    expect(prismaMock.user.update).not.toHaveBeenCalled();
    // Возвращённая транзакция всё равно помечена отозванной — точечно.
    expect(prismaMock.transactionRecord.updateMany).toHaveBeenCalledWith({
      where: { transactionId: 'tx-1' },
      data: { revocationDate: new Date(refundSignedAt) },
    });
    expect(
      logAuditMock.mock.calls.some(
        (c: any[]) => c[0].action === 'billing.webhook.revocation_skipped',
      ),
    ).toBe(true);

    await app.close();
  });

  it('REFUND без более свежего продления гасит право как раньше', async () => {
    const refundSignedAt = Date.now() - 3600 * 1000;
    mockNotification('REFUND', { signedDate: refundSignedAt, revocationDate: refundSignedAt });
    prismaMock.appleNotification.create.mockResolvedValue({});
    mockKnownNotifications([]);
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(200);
    expect(prismaMock.subscription.updateMany.mock.calls[0][0].data).toEqual({
      isActive: false,
      revokedAt: new Date(refundSignedAt),
    });
    expect(prismaMock.user.update).toHaveBeenCalledWith({
      where: { id: USER_ID },
      data: { isPremium: false, premiumUntil: null },
    });

    await app.close();
  });

  it('ошибка обработки снимает заявку, чтобы ретрай Apple не отбросился как дубликат', async () => {
    mockNotification('DID_RENEW');
    prismaMock.appleNotification.create.mockResolvedValue({});
    prismaMock.subscription.updateMany.mockRejectedValue(new Error('db down'));
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/billing/webhooks/apple',
      payload: { signedPayload: 'notif.jws.sig' },
    });

    expect(res.statusCode).toBe(500);
    expect(prismaMock.appleNotification.delete).toHaveBeenCalledWith({
      where: { notificationUUID: NOTIF_UUID },
    });

    await app.close();
  });
});
