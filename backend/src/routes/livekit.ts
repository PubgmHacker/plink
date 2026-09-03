// src/routes/livekit.ts — Stage 9: LiveKit SFU token endpoint
import type { FastifyPluginAsync } from 'fastify';
import { config } from '../config/index.js';
import { prisma } from '../config/db.js';

/**
 * Решение продукта 02.08.2026: голос и видеочат В КОМНАТЕ — функция Плинк+.
 * Голос в личных сообщениях остаётся бесплатным для всех и через этот
 * эндпоинт не ходит (голосовые сообщения живут в routes/messages.ts).
 *
 * Проверка обязана быть НА СЕРВЕРЕ. До правки 02.08.2026 /rtc/token выдавал
 * токен с `canPublish: true` любому участнику комнаты: спрятать кнопку
 * в интерфейсе — не защита, такой запрос повторяется curl'ом за минуту.
 */
async function hasActivePlus(userId: string): Promise<boolean> {
  const now = new Date();

  // Источник истины — подписка: только она знает про отзыв (revokedAt)
  // и про реальный срок. Опираться только на User.isPremium нельзя: флаг
  // может не успеть сброситься после возврата средств.
  const sub = await prisma.subscription.findFirst({
    where: {
      userID: userId,
      isActive: true,
      revokedAt: null,
      expiresAt: { gt: now },
    },
    select: { id: true },
  });
  if (sub) return true;

  // Запасной путь: премиум, выданный не покупкой — промо, реферальные
  // дни, ручная выдача админом. Флаг без срока не принимаем: истёкший
  // premiumUntil означает, что доступ кончился.
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { isPremium: true, premiumUntil: true },
  });
  return !!(user?.isPremium && user.premiumUntil && user.premiumUntil > now);
}

/**
 * БЕТА-РЕЖИМ (02.08.2026). На бета-тесте нужно прогнать все экраны,
 * включая экран покупки Плинк+, поэтому пэйволл можно показать РАНЬШЕ
 * проверки доступности SFU — даже когда ключей LiveKit ещё нет.
 *
 * Флаг был fail-open — `!== 'false'` означало «включено,
 * пока явно не выключили». То есть любой свежий деплой (Railway без переменной,
 * новый стейдж, локальный запуск) по умолчанию ПРОДАВАЛ подписку за неработающую
 * функцию, а защитой служил комментарий «не забыть перед App Store». Требование
 * Guideline 3.1.1 нельзя охранять человеческой памятью: теперь режим включается
 * только явным RTC_PAYWALL_BEFORE_AVAILABILITY=true, а по умолчанию выключен.
 * Дефолт безопасен, беты — осознанный опт-ин.
 */
const PAYWALL_BEFORE_AVAILABILITY = process.env.RTC_PAYWALL_BEFORE_AVAILABILITY === 'true';

export const livekitRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.post(
    '/rtc/token',
    {
      preHandler: [(fastify as any).authenticate],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request: any, reply: any) => {
      const userId = request.user.id;
      const { roomId } = request.body ?? {};
      if (!roomId) return reply.status(400).send({ error: 'roomId required' });

      const [participant, room] = await Promise.all([
        prisma.roomParticipant
          .findUnique({
            where: { roomID_userID: { roomID: roomId, userID: userId } },
            select: { id: true },
          })
          .catch(() => null),
        prisma.room.findUnique({
          where: { id: roomId },
          select: { hostID: true, isActive: true },
        }),
      ]);
      if (!room || !room.isActive) return reply.status(404).send({ error: 'Room not found' });
      if (room.hostID !== userId && !participant)
        return reply.status(403).send({ error: 'Not a room member' });

      const sfuReady = !!(
        config.LIVEKIT_URL &&
        config.LIVEKIT_API_KEY &&
        config.LIVEKIT_API_SECRET
      );

      // 402 отделён от 403 намеренно: 403 значит «тебе сюда нельзя»
      // (не участник комнаты), 402 — «можно, если оформишь Плинк+».
      // Именно по 402 клиент открывает экран подписки, а не алерт с ошибкой.
      const denyWithoutPlus = async () => {
        if (await hasActivePlus(userId)) return null;
        return reply.status(402).send({
          error: 'subscription_required',
          reason: 'plus_required',
          feature: 'room_rtc',
          product: 'plink_plus',
          message: 'Голос и видеочат в комнате доступны с подпиской Плинк+',
        });
      };

      const denyWithoutSfu = () => {
        if (sfuReady) return null;
        return reply.status(503).send({
          error: 'RTC unavailable',
          reason: 'not_configured',
          message: 'Голос и видео в комнате пока не включены',
        });
      };

      // Бета: сначала пэйволл — обычный пользователь видит экран покупки
      // даже без ключей LiveKit. Подписчик при этом получает честное «скоро»,
      // а не молчаливый обрыв — два состояния остаются различимыми.
      // Прод: сначала доступность — не продаём то, чего нет.
      if (PAYWALL_BEFORE_AVAILABILITY) {
        const paywall = await denyWithoutPlus();
        if (paywall) return paywall;
        const unavailable = denyWithoutSfu();
        if (unavailable) return unavailable;
      } else {
        const unavailable = denyWithoutSfu();
        if (unavailable) return unavailable;
        const paywall = await denyWithoutPlus();
        if (paywall) return paywall;
      }

      const identity = userId;
      const roomName = `plink-${roomId}`;
      const isHost = room.hostID === userId;
      const now = Math.floor(Date.now() / 1000);
      const ttl = 3600;

      const { SignJWT } = await import('jose');
      const secret = new TextEncoder().encode(config.LIVEKIT_API_SECRET);
      const token = await new SignJWT({
        video: {
          room: roomName,
          roomJoin: true,
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        },
        ...(isHost ? { roomAdmin: true } : {}),
      })
        .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
        .setIssuer(config.LIVEKIT_API_KEY)
        .setSubject(identity)
        .setIssuedAt(now)
        .setExpirationTime(now + ttl)
        .sign(secret);

      return reply.send({
        token,
        url: config.LIVEKIT_URL,
        roomName,
        identity,
        expiresInSec: ttl,
        audio: {
          codec: 'opus',
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: { simulcast: true, adaptiveSubscription: true, dynacast: true },
        e2ee: false,
      });
    },
  );

  const livekitConfigured = () =>
    !!(config.LIVEKIT_URL && config.LIVEKIT_API_KEY && config.LIVEKIT_API_SECRET);

  /** Public — clients poll this to show/hide mic UI (no secrets leaked). */
  fastify.get(
    '/rtc/status',
    {
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (_req: any, reply: any) => {
      return reply.send({
        livekitEnabled: livekitConfigured(),
        livekitSfuFlag: config.LIVEKIT_SFU,
        // Эндпоинт публичный, про конкретного человека здесь сказать нечего.
        // Сам факт «функция платная» — не секрет, он написан на витрине.
        requiresPlus: true,
      });
    },
  );

  fastify.get(
    '/rtc/config',
    {
      preHandler: [(fastify as any).authenticate],
    },
    async (request: any, reply: any) => {
      // Отдаём hasPlus, чтобы iOS рисовал замок на кнопках сразу, а не узнавал
      // о пэйволле только после неудачного запроса за токеном.
      const hasPlus = await hasActivePlus(request.user.id);
      return reply.send({
        livekitEnabled: livekitConfigured(),
        livekitUrl: livekitConfigured() ? config.LIVEKIT_URL : null,
        meshFallbackThreshold: 4,
        e2eeSupported: false,
        requiresPlus: true,
        hasPlus,
        // Бета: клиент показывает кнопку микрофона активной даже без SFU,
        // чтобы тап дошёл до сервера и вернул 402 → экран покупки.
        paywallBeforeAvailability: PAYWALL_BEFORE_AVAILABILITY,
      });
    },
  );
};
