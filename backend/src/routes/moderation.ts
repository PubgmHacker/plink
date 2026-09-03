// moderation.ts — Plink M39, переписан по аудиту 26.07.2026
//
// Формальные механизмы модерации, которые требует App Review для любого UGC:
// жалоба → реакция за 24 часа → возможность заблокировать обидчика.
// ИИ-модерация из M16 остаётся и работает параллельно — она не заменяет эти механизмы.
//
// ⚠️ ЧТО БЫЛО СЛОМАНО (файл был подключён в app.ts и ронял бы сервер):
//
//   1. Экспорт был ТОЛЬКО именованным (`export async function moderationRoutes`),
//      а app.ts импортирует его как default. При деплое `fastify.register(undefined)`
//      падает на старте. Теперь есть и default, и именованный экспорт.
//
//   2. Модуль создавал СВОЙ `new PrismaClient()` вместо общего из config/db.
//      Это второй пул соединений к Postgres и лишний расход лимита Railway.
//
//   3. Обращения к БД были написаны под несуществующую схему:
//        `prisma.block`            → на самом деле `userBlock`
//        `prisma.message`          → на самом деле `chatMessage`
//        `blockerId/blockedId`     → в схеме `blockerID/blockedID`
//        `userId/friendId`         → в схеме `userID/friendID`
//        `user.isModerator`        → в схеме `role: UserRole`
//        `report.reporterId`       → в схеме `reporterID`
//      Поля `targetType/targetID/comment/dueAt/resolution` и флаги
//      `hidden`/`shadowbanned` в схеме отсутствовали — добавлены миграцией
//      20260726120000_moderation_gdpr_indexes.
//
//   4. Маршруты не требовали авторизации: `userId(request)` читал
//      `request.user`, который без preHandler `authenticate` всегда пуст,
//      поэтому ЛЮБОЙ запрос получал 401 — модерация не работала вообще.

import type { FastifyInstance, FastifyRequest } from 'fastify';
import { prisma } from '../config/db.js';
import { invalidateUserSnapshot } from '../middleware/auth.js';

const SLA_HOURS = 24;
const AUTO_HIDE_THRESHOLD = 3;
/// Срок бана по решению из очереди жалоб. Бессрочный бан остаётся
/// прерогативой админки (/admin/users/:id/ban с обязательной причиной).
const MODERATION_BAN_DAYS = 30;

const REASONS = [
  'spam',
  'harassment',
  'hate',
  'sexual',
  'violence',
  'illegal',
  'copyright',
  'other',
] as const;
const TARGET_TYPES = ['user', 'message', 'room'] as const;

type Reason = (typeof REASONS)[number];
type TargetType = (typeof TARGET_TYPES)[number];

/// Роли, которым доступна очередь разбора. В схеме нет флага isModerator —
/// права определяются перечислением UserRole.
const MODERATOR_ROLES = new Set(['MODERATOR', 'ADMIN', 'FOUNDER']);

function userId(request: FastifyRequest): string | undefined {
  return (request as any).user?.id;
}

async function isModerator(id: string): Promise<boolean> {
  const actor = await prisma.user.findUnique({ where: { id }, select: { role: true } });
  return actor ? MODERATOR_ROLES.has(String(actor.role)) : false;
}

/// Когда на объект поступает три независимые жалобы, мы скрываем его до разбора.
/// Лучше ошибочно скрыть на пару часов, чем оставить травлю в эфире.
///
/// Считаем именно РАЗНЫХ заявителей: иначе один человек тремя жалобами
/// скрывал бы чужое сообщение.
///
/// Автодействие — ТОЛЬКО для контента (message/room).
/// Для targetType='user' автошадоу-бана нет: три сговорившихся самореганных
/// аккаунта устраивали DoS любому пользователю до ручного разбора (SLA 24 ч).
/// Жалобы на пользователя остаются в очереди и разбираются модератором.
async function autoHide(targetType: TargetType, targetId: string): Promise<boolean> {
  if (targetType === 'user') return false;

  const rows = await prisma.report.findMany({
    where: { targetType, targetID: targetId, resolvedAt: null },
    select: { reporterID: true },
    distinct: ['reporterID'],
  });
  if (rows.length < AUTO_HIDE_THRESHOLD) return false;

  try {
    if (targetType === 'message') {
      await prisma.chatMessage.update({ where: { id: targetId }, data: { hidden: true } });
    } else {
      await prisma.room.update({ where: { id: targetId }, data: { hidden: true } });
    }
    return true;
  } catch {
    // Объект мог быть уже удалён — жалоба всё равно остаётся в очереди.
    return false;
  }
}

/// Есть ли по этому объекту уже вынесенное решение ban/hide (по ДРУГОЙ жалобе)?
/// Нужно, чтобы dismiss одной ложной жалобы не снимал ограничение,
/// наложенное другим модератором — это верно для всех targetType,
/// а не только для user (аудит 26.07.2026).
///
/// Жалобы, закрытые тем же самым решением, что и разбираемая (updateMany
/// ставит им одинаковый resolvedAt), чужим ограничением не считаются:
/// иначе повторный dismiss той же жалобы не мог бы отменить своё же решение.
async function hasEnforcedDecision(
  targetType: TargetType,
  targetId: string,
  report: { id: string; resolvedAt: Date | null },
): Promise<boolean> {
  const count = await prisma.report.count({
    where: {
      targetType,
      id: { not: report.id },
      resolvedAt: { not: null },
      resolution: { in: ['ban', 'hide'] },
      // Legacy-жалобы на комнаты хранят объект только в roomID.
      OR: [{ targetID: targetId }, { targetID: null, roomID: targetId }],
      ...(report.resolvedAt ? { AND: [{ resolvedAt: { not: report.resolvedAt } }] } : {}),
    },
  });
  return count > 0;
}

/// Снять ограничение с объекта. Возвращает true, если запись действительно
/// обновлена (объект мог быть уже удалён).
///
/// bannedUntil снимаем: при явном unban — всегда; при отмене своего же решения
/// (dismiss по жалобе, закрытой как 'ban') — тоже, а вот при dismiss жалобы,
/// по которой бана не выносили, не трогаем: иначе ложная жалоба отменяла бы
/// бессрочный бан из админки (/admin/users/:id/ban).
async function liftRestriction(
  targetType: TargetType,
  targetId: string,
  revertingReport?: { resolution: string | null; resolvedAt: Date | null },
): Promise<boolean> {
  try {
    if (targetType === 'message') {
      await prisma.chatMessage.update({ where: { id: targetId }, data: { hidden: false } });
    } else if (targetType === 'room') {
      await prisma.room.update({ where: { id: targetId }, data: { hidden: false } });
    } else {
      const clearBan =
        !revertingReport ||
        (revertingReport.resolution === 'ban' && revertingReport.resolvedAt !== null);
      await prisma.user.update({
        where: { id: targetId },
        data: clearBan ? { shadowbanned: false, bannedUntil: null } : { shadowbanned: false },
      });
      invalidateUserSnapshot(targetId);
    }
    return true;
  } catch {
    return false;
  }
}

export async function moderationRoutes(fastify: FastifyInstance) {
  // —— Жалоба ——
  fastify.post<{
    Body: { targetType: TargetType; targetId: string; reason: Reason; comment?: string };
  }>(
    '/moderation/report',
    {
      preHandler: [(fastify as any).authenticate],
      config: {
        rateLimit: {
          max: 20,
          timeWindow: '1 hour',
          keyGenerator: (r: FastifyRequest) => userId(r) ?? (r as any).ip,
        },
      },
    },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });

      const { targetType, targetId, reason, comment } = request.body ?? ({} as any);

      if (!TARGET_TYPES.includes(targetType))
        return reply.code(400).send({ error: 'invalid_target_type' });
      if (!REASONS.includes(reason)) return reply.code(400).send({ error: 'invalid_reason' });
      if (typeof targetId !== 'string' || targetId.length === 0 || targetId.length > 64) {
        return reply.code(400).send({ error: 'invalid_target_id' });
      }
      if (targetType === 'user' && targetId === me) {
        return reply.code(400).send({ error: 'cannot_report_self' });
      }

      const dueAt = new Date(Date.now() + SLA_HOURS * 60 * 60 * 1000);

      const report = await prisma.report.create({
        data: {
          reporterID: me,
          targetType,
          targetID: targetId,
          // Для жалоб на комнату сохраняем и типизированную связь —
          // так старые отчёты и админка продолжают работать.
          roomID: targetType === 'room' ? targetId : null,
          reason,
          comment: typeof comment === 'string' ? comment.slice(0, 1000) : null,
          dueAt,
        },
      });

      const hidden = await autoHide(targetType, targetId);

      return reply
        .code(201)
        .send({ id: report.id, dueAt, slaHours: SLA_HOURS, autoHidden: hidden });
    },
  );

  // —— Блокировка ——
  fastify.post<{ Body: { userId: string } }>(
    '/moderation/block',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });

      const target = request.body?.userId;
      if (typeof target !== 'string' || target.length === 0 || target === me) {
        return reply.code(400).send({ error: 'invalid_user' });
      }

      const exists = await prisma.user.findUnique({ where: { id: target }, select: { id: true } });
      if (!exists) return reply.code(404).send({ error: 'user_not_found' });

      await prisma.userBlock.upsert({
        where: { blockerID_blockedID: { blockerID: me, blockedID: target } },
        create: { blockerID: me, blockedID: target },
        update: {},
      });

      // Блокировка разрывает дружбу в обе стороны — иначе человек остаётся
      // в списке друзей и продолжает видеть присутствие.
      await prisma.friendship
        .deleteMany({
          where: {
            OR: [
              { userID: me, friendID: target },
              { userID: target, friendID: me },
            ],
          },
        })
        .catch(() => {});

      // Висящие заявки в друзья тоже убираем, иначе блокировка обходится
      // повторным принятием старого запроса.
      await prisma.friendRequest
        .deleteMany({
          where: {
            OR: [
              { fromUserID: me, toUserID: target },
              { fromUserID: target, toUserID: me },
            ],
          },
        })
        .catch(() => {});

      return reply.send({ ok: true });
    },
  );

  fastify.delete<{ Params: { userId: string } }>(
    '/moderation/block/:userId',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });

      await prisma.userBlock.deleteMany({
        where: { blockerID: me, blockedID: request.params.userId },
      });
      return reply.send({ ok: true });
    },
  );

  fastify.get(
    '/moderation/blocked',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });

      const rows = await prisma.userBlock.findMany({
        where: { blockerID: me },
        select: { blockedID: true },
      });
      return reply.send({ blockedUserIds: rows.map((r: { blockedID: string }) => r.blockedID) });
    },
  );

  // —— Очередь для модераторов ——
  fastify.get(
    '/moderation/queue',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });
      if (!(await isModerator(me))) return reply.code(403).send({ error: 'forbidden' });

      const reports = await prisma.report.findMany({
        where: { resolvedAt: null },
        orderBy: { dueAt: 'asc' },
        take: 100,
      });

      const now = Date.now();
      return reply.send({
        total: reports.length,
        // dueAt может отсутствовать у записей, созданных до миграции.
        overdue: reports.filter(
          (r: { dueAt: Date | null }) => r.dueAt !== null && r.dueAt.getTime() < now,
        ).length,
        reports,
      });
    },
  );

  fastify.post<{ Params: { id: string }; Body: { action: 'dismiss' | 'hide' | 'ban' | 'unban' } }>(
    '/moderation/queue/:id/resolve',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });
      if (!(await isModerator(me))) return reply.code(403).send({ error: 'forbidden' });

      const report = await prisma.report.findUnique({ where: { id: request.params.id } });
      if (!report) return reply.code(404).send({ error: 'not_found' });

      const action = request.body?.action ?? 'dismiss';
      // 'unban' снимает ограничение по конкретной жалобе; dismiss этого больше
      // не делает, если по объекту есть чужое решение ban/hide. Разбан без
      // жалобы — POST /moderation/users/:id/unban.
      if (!['dismiss', 'hide', 'ban', 'unban'].includes(action)) {
        return reply.code(400).send({ error: 'invalid_action' });
      }

      const targetType = (report.targetType ?? 'room') as TargetType;
      const targetId = report.targetID ?? report.roomID;
      if (!targetId) return reply.code(400).send({ error: 'report_without_target' });

      // Что фактически сделали — отдаём в ответе, иначе «пропавший разбан»
      // выглядел как успех. Форму ответа никто не парсит (iOS этот эндпоинт
      // не вызывает вовсе), расширение безопасно.
      let restricted = false;
      let lifted = false;
      let enforcementKept = false;

      if (action === 'ban' || action === 'hide') {
        try {
          if (targetType === 'message') {
            await prisma.chatMessage.update({ where: { id: targetId }, data: { hidden: true } });
          } else if (targetType === 'room') {
            await prisma.room.update({ where: { id: targetId }, data: { hidden: true } });
          } else {
            // shadowbanned прячет публичный профиль (routes/web.ts), но НИЧЕГО не
            // ограничивает в API/WS: его нет ни в UserSnapshot (middleware/auth.ts),
            // ни в проверках gateway.ts. Поэтому 'ban' дополнительно выставляет
            // bannedUntil — именно его сверяют authenticate и шлюз.
            await prisma.user.update({
              where: { id: targetId },
              data:
                action === 'ban'
                  ? {
                      shadowbanned: true,
                      bannedUntil: new Date(Date.now() + MODERATION_BAN_DAYS * 24 * 60 * 60 * 1000),
                    }
                  : { shadowbanned: true },
            });
            // Бан должен действовать сразу, а не через TTL кэша авторизации.
            invalidateUserSnapshot(targetId);
          }
          restricted = true;
        } catch {
          // Объект мог быть уже удалён — жалобу всё равно закрываем,
          // но в ответе честно говорим, что ограничение не наложено.
          restricted = false;
        }
      }

      // Явное снятие ограничений — отдельное действие модератора.
      if (action === 'unban') {
        lifted = await liftRestriction(targetType, targetId);
      }

      if (action === 'dismiss') {
        // Отменяем ограничение, если жалобы оказались ложными.
        //
        // Раньше dismiss снимал его безусловно —
        // отклонение одной ложной жалобы молча отменяло решение другого
        // модератора по другой жалобе на тот же объект. Проверка нужна для
        // всех targetType: скрытие комнаты/сообщения ручным 'hide' снималось
        // так же молча. Для принудительного снятия есть action: 'unban'.
        if (await hasEnforcedDecision(targetType, targetId, report)) {
          enforcementKept = true;
        } else {
          lifted = await liftRestriction(targetType, targetId, report);
        }
      }

      // Закрываем все открытые жалобы на этот же объект одним решением.
      // Саму разбираемую жалобу закрываем всегда: у legacy-записей объект
      // лежит только в roomID, и фильтр по targetID их не находил — жалоба
      // оставалась в очереди навсегда, хотя действие уже применено.
      const closed = await prisma.report.updateMany({
        where: {
          OR: [
            { id: report.id },
            {
              targetType,
              resolvedAt: null,
              OR: [{ targetID: targetId }, { targetID: null, roomID: targetId }],
            },
          ],
        },
        data: {
          resolvedAt: new Date(),
          resolvedBy: me,
          resolution: action,
          status: action === 'ban' || action === 'hide' ? 'resolved' : 'dismissed',
        },
      });

      return reply.send({ ok: true, restricted, lifted, enforcementKept, closed: closed.count });
    },
  );

  // —— Прямое снятие ограничений с пользователя ——
  //
  // action:'unban' требует id жалобы, а разобранные жалобы не отдаёт ни одна
  // выдача (/moderation/queue фильтрует resolvedAt:null, админка — status
  // 'pending'). В состоянии «пользователь забанен, новых жалоб нет» модератору
  // просто некуда послать unban, поэтому нужен путь без привязки к жалобе.
  fastify.post<{ Params: { id: string } }>(
    '/moderation/users/:id/unban',
    { preHandler: [(fastify as any).authenticate] },
    async (request, reply) => {
      const me = userId(request);
      if (!me) return reply.code(401).send({ error: 'unauthorized' });
      if (!(await isModerator(me))) return reply.code(403).send({ error: 'forbidden' });

      const target = await prisma.user.findUnique({
        where: { id: request.params.id },
        select: { id: true },
      });
      if (!target) return reply.code(404).send({ error: 'user_not_found' });

      const lifted = await liftRestriction('user', target.id);
      return reply.send({ ok: true, lifted });
    },
  );
}

// app.ts импортирует этот модуль как default — без этой строки
// `fastify.register(undefined)` роняет сервер на старте.
export default moderationRoutes;
