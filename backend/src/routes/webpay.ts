// webpay.ts — веб-оплата Plink+ через ЮKassa (задача «подписка через сайт»).
//
// Флоу:
//   1. Страница /plus (web.ts) отправляет POST /api/webpay/create
//      { email, password, plan } — вход по существующему аккаунту Plink.
//   2. Мы создаём платёж в ЮKassa (confirmation: redirect) и возвращаем
//      confirmationUrl — страница уводит пользователя на оплату.
//   3. ЮKassa присылает webhook payment.succeeded. Телу вебхука НЕ доверяем:
//      перепроверяем платёж GET-запросом к API ЮKassa по id и только после
//      этого выдаём подписку.
//   4. Грант пишет ТЕ ЖЕ поля, что и покупка в приложении (billing.ts):
//      Subscription + User.isPremium/premiumUntil. Приложение подхватывает
//      автоматически: на каждом запуске оно читает
//      GET /api/billing/entitlements — server-authoritative.
//
// Fail-closed: без YOOKASSA_SHOP_ID/YOOKASSA_SECRET_KEY маршруты отдают 503.
// Продление НЕ автоматическое (разовый платёж на период) — автосписания
// требуют сохранённого способа оплаты, это отдельный этап.
//
// ⚠️ App Review 3.1.1: из iOS-приложения НЕЛЬЗЯ ссылаться на /plus.
// Веб-страница живёт независимо (как у Spotify) — это разрешено.

import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { prisma } from '../config/db.js';
import { logAudit } from '../utils/audit.js';

const SHOP_ID = process.env.YOOKASSA_SHOP_ID ?? '';
const SECRET_KEY = process.env.YOOKASSA_SECRET_KEY ?? '';
const SEND_RECEIPT = process.env.YOOKASSA_SEND_RECEIPT === 'true';
const PUBLIC_ORIGIN = process.env.PUBLIC_ORIGIN ?? 'https://plink.app';
const YK_API = 'https://api.yookassa.ru/v3';

export type WebPlanId = '1m' | '3m' | '12m';

export const WEB_PLANS: Record<WebPlanId, { title: string; days: number; price: string }> = {
  '1m':  { title: 'Plink+ на месяц',    days: 30,  price: process.env.PLUS_PRICE_1M  ?? '199.00' },
  '3m':  { title: 'Plink+ на 3 месяца', days: 90,  price: process.env.PLUS_PRICE_3M  ?? '499.00' },
  '12m': { title: 'Plink+ на год',      days: 365, price: process.env.PLUS_PRICE_12M ?? '1490.00' },
};

export function webPayConfigured(): boolean {
  return Boolean(SHOP_ID && SECRET_KEY);
}

function ykAuthHeader(): string {
  return 'Basic ' + Buffer.from(`${SHOP_ID}:${SECRET_KEY}`).toString('base64');
}

async function ykFetch(path: string, init: { method?: string; body?: unknown; idempotenceKey?: string } = {}) {
  const res = await fetch(`${YK_API}${path}`, {
    method: init.method ?? 'GET',
    headers: {
      Authorization: ykAuthHeader(),
      'Content-Type': 'application/json',
      ...(init.idempotenceKey ? { 'Idempotence-Key': init.idempotenceKey } : {}),
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
    // ЮKassa обычно отвечает за секунды; зависший платёжный API не должен
    // держать HTTP-хендлер бесконечно. Idempotence-Key делает ретрай безопасным.
    signal: AbortSignal.timeout(15_000),
  });
  const json: any = await res.json().catch(() => null);
  return { status: res.status, json };
}

/// Ревью 26.07.2026: Serializable-транзакция гранта обновляет строку User, а её
/// пишут и другие ручки (например POST /auth/heartbeat, user.update isOnline),
/// поэтому конфликт сериализации (P2034 / SQLSTATE 40001) возможен и БЕЗ гонки
/// платежей. Транзакция идемпотентна (проверка дубликата внутри неё), поэтому
/// повторяем её сами, а не отдаём 500 и не ждём ретрая ЮKassa.
function isSerializationFailure(e: any): boolean {
  return e?.code === 'P2034'
    || e?.meta?.code === '40001'
    || /40001|could not serialize|deadlock detected/i.test(String(e?.message ?? ''));
}

async function withSerializableRetry<T>(run: () => Promise<T>, attempts = 3): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await run();
    } catch (e: any) {
      if (attempt >= attempts || !isSerializationFailure(e)) throw e;
      await new Promise((resolve) => setTimeout(resolve, 25 * attempt));
    }
  }
}

/// Выдача Plink+ — та же семантика, что у покупки в приложении.
/// Идемпотентна по paymentId (хранится в Subscription.originalTransactionId).
/// Экспортирована для теста грант-пути (scripts/test-web-premium.mjs).
///
/// Раньше проверка «уже выдано?» шла ДО транзакции
/// (check-then-act), а уникального ограничения на originalTransactionId в БД
/// не было. ЮKassa доставляет payment.succeeded повторно и ретраит на не-2xx —
/// две пересекающиеся доставки выдавали премиум дважды.
///
/// Теперь (миграция 20260726120500_billing_idempotency) на
/// Subscription.originalTransactionId есть @unique, и повтор отбивает база
/// (P2002) — это единственный надёжный арбитр ГОНКИ. Проверка «уже выдано?»
/// оставлена ВНУТРИ транзакции вторым эшелоном: она гонку не закрывает, но
/// спасает от тихой двойной выдачи на базе, где миграция ещё не применена
/// (см. комментарий у findFirst ниже). Транзакция остаётся
/// Serializable, потому что продление читает User.premiumUntil и считает от
/// него (накопление срока), а вставка подписки идёт ДО user.update — на
/// дубликате премиум не продлевается вовсе.
export async function grantWebPremium(userId: string, plan: WebPlanId, paymentId: string): Promise<'granted' | 'duplicate'> {
  const externalId = `yookassa:${paymentId}`;
  const days = WEB_PLANS[plan].days;

  try {
    await withSerializableRetry(() => prisma.$transaction(async (tx) => {
      const user = await tx.user.findUnique({
        where: { id: userId },
        select: { premiumUntil: true, isPremium: true },
      });
      // Продление копится: считаем от текущего конца подписки, если он в будущем.
      const now = new Date();
      const base = user?.isPremium && user.premiumUntil && user.premiumUntil > now
        ? user.premiumUntil
        : now;
      const until = new Date(base.getTime() + days * 24 * 3600 * 1000);

      // Ревью 26.07.2026: второй эшелон против повторной доставки. Главный
      // арбитр гонки — уникальный индекс (P2002 ниже), но если код выкачен
      // раньше `prisma migrate deploy` (или миграция пропущена в start.sh),
      // индекса нет и вставка проходит МОЛЧА: премиум продлевается второй раз,
      // в логах ни ошибки, ни предупреждения. Чтение внутри Serializable-
      // транзакции закрывает последовательные ретраи ЮKassa и на такой базе.
      const already = await tx.subscription.findFirst({
        where: { originalTransactionId: externalId },
        select: { id: true },
      });
      if (already) {
        const err: any = new Error('web payment already granted');
        err.plinkCode = 'duplicate_web_payment';
        throw err;
      }

      await tx.subscription.create({
        data: {
          userID: userId,
          plan: `web-${plan}`,
          isActive: true,
          expiresAt: until,
          originalTransactionId: externalId,
          environment: 'Production',
          lastVerifiedAt: now,
        },
      });
      await tx.user.update({
        where: { id: userId },
        data: { isPremium: true, premiumUntil: until },
      });
    }, { isolationLevel: 'Serializable' }));
  } catch (e: any) {
    // P2002 — уникальное ограничение на Subscription.originalTransactionId:
    // этот платёж уже выдан (повторная доставка вебхука или гонка двух
    // доставок). Транзакция откатилась ДО user.update, поэтому срок подписки
    // не продлился второй раз — повтор это чистый no-op.
    if (e?.code === 'P2002' || e?.plinkCode === 'duplicate_web_payment') return 'duplicate';
    throw e;
  }

  await logAudit({
    userId,
    action: 'billing.web_purchase',
    metadata: { plan, paymentId, provider: 'yookassa' },
  });
  return 'granted';
}

export default async function webpayRoutes(fastify: any) {
  // ── Создание платежа ────────────────────────────────────────────────
  fastify.post('/webpay/create', {
    config: { rateLimit: { max: 10, timeWindow: '10 minutes' } },
  }, async (request: any, reply: any) => {
    if (!webPayConfigured()) {
      return reply.status(503).send({ error: 'Оплата на сайте пока не подключена. Оформите Plink+ в приложении.' });
    }

    const { email, password, plan } = request.body ?? {};
    if (typeof email !== 'string' || typeof password !== 'string' || !(plan in WEB_PLANS)) {
      return reply.status(400).send({ error: 'Нужны email, пароль и тариф.' });
    }

    const user = await prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } })
      ?? await prisma.user.findUnique({ where: { email: email.trim() } });
    if (!user || !(await bcrypt.compare(password, user.password))) {
      await logAudit({ action: 'billing.web_login_failed', ip: request.ip, metadata: { email } });
      return reply.status(401).send({ error: 'Неверный email или пароль.' });
    }
    if (user.bannedUntil && user.bannedUntil > new Date()) {
      return reply.status(403).send({ error: 'Аккаунт заблокирован.' });
    }
    if (user.deletedAt) {
      return reply.status(403).send({ error: 'Аккаунт удалён.' });
    }

    const planDef = WEB_PLANS[plan as WebPlanId];
    const body: any = {
      amount: { value: planDef.price, currency: 'RUB' },
      capture: true,
      confirmation: { type: 'redirect', return_url: `${PUBLIC_ORIGIN}/plus/success` },
      description: `${planDef.title} — @${user.username}`,
      metadata: { userId: user.id, plan },
    };
    if (SEND_RECEIPT) {
      // 54-ФЗ: чек нужен, если у магазина включена фискализация.
      body.receipt = {
        customer: { email: user.email },
        items: [{
          description: planDef.title,
          quantity: '1.00',
          amount: { value: planDef.price, currency: 'RUB' },
          vat_code: 1,
        }],
      };
    }

    const created = await ykFetch('/payments', {
      method: 'POST',
      body,
      idempotenceKey: crypto.randomUUID(),
    });
    const confirmationUrl = created.json?.confirmation?.confirmation_url;
    if (created.status >= 300 || !confirmationUrl) {
      request.log.error({ ykStatus: created.status, yk: created.json?.type, desc: created.json?.description }, 'yookassa create failed');
      return reply.status(502).send({ error: 'Платёжный сервис недоступен, попробуйте позже.' });
    }

    await logAudit({
      userId: user.id,
      action: 'billing.web_checkout_started',
      ip: request.ip,
      metadata: { plan, paymentId: created.json.id },
    });
    return reply.send({ confirmationUrl });
  });

  // ── Webhook ЮKassa ──────────────────────────────────────────────────
  // Аутентификации у вебхуков ЮKassa нет — поэтому телу не доверяем вовсе:
  // берём только object.id и перепроверяем платёж напрямую в API.
  fastify.post('/webpay/yookassa/webhook', {
    config: { rateLimit: { max: 120, timeWindow: '1 minute' } },
  }, async (request: any, reply: any) => {
    if (!webPayConfigured()) return reply.status(503).send({ ok: false });

    const paymentId = request.body?.object?.id;
    if (typeof paymentId !== 'string' || !/^[a-z0-9-]{20,64}$/i.test(paymentId)) {
      return reply.status(400).send({ ok: false });
    }

    const payment = await ykFetch(`/payments/${paymentId}`);
    if (payment.status !== 200 || !payment.json) {
      // Транзиентная ошибка — 500, чтобы ЮKassa повторила доставку.
      return reply.status(500).send({ ok: false });
    }

    const { status, metadata } = payment.json;
    const userId = metadata?.userId;
    const plan = metadata?.plan as WebPlanId | undefined;

    if (status !== 'succeeded' || !userId || !plan || !(plan in WEB_PLANS)) {
      // Не наш кейс (waiting_for_capture/canceled/чужой платёж) — подтверждаем
      // получение, чтобы не копить ретраи.
      return reply.send({ ok: true, ignored: true });
    }

    const result = await grantWebPremium(String(userId), plan, paymentId);
    return reply.send({ ok: true, result });
  });

  // ── Статус для страницы /plus (что вообще доступно) ────────────────
  fastify.get('/webpay/status', async (_request: any, reply: any) => {
    reply.send({
      enabled: webPayConfigured(),
      plans: Object.fromEntries(
        Object.entries(WEB_PLANS).map(([id, p]) => [id, { title: p.title, price: p.price, days: p.days }]),
      ),
    });
  });
}
