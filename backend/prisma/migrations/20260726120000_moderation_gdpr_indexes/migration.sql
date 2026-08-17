-- Аудит 26.07.2026 — три независимые проблемы в одной миграции.
--
-- 1) МОДЕРАЦИЯ. `routes/moderation.ts` (M39) написан под модель Report,
--    которая умеет жалобы на СООБЩЕНИЯ и ПОЛЬЗОВАТЕЛЕЙ, а в схеме Report
--    привязан только к комнате (`roomID`). Из-за этого модуль падал на
--    первом же запросе. App Review требует возможность пожаловаться именно
--    на конкретное сообщение и на конкретного человека, поэтому расширяем
--    модель, а не урезаем функциональность.
--
-- 2) GDPR. У ~13 связей не задан onDelete: `prisma.user.delete()` падал по
--    внешнему ключу, а ручное удаление рисковало оставить персональные
--    данные в чужих таблицах. Проставляем явные правила.
--
-- 3) ПРОИЗВОДИТЕЛЬНОСТЬ. Горячий запрос личных сообщений сортирует по
--    createdAt, но составного индекса под него не было.
--
-- Миграция АДДИТИВНАЯ: существующие данные не удаляются и не меняются,
-- кроме заполнения targetID у старых жалоб (копией roomID).

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Модерация
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "targetType" TEXT NOT NULL DEFAULT 'room';
ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "targetID"   TEXT;
ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "comment"    TEXT;
ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "dueAt"      TIMESTAMP(3);
ALTER TABLE "Report" ADD COLUMN IF NOT EXISTS "resolution" TEXT;

-- Старые жалобы были только на комнаты — переносим ссылку в общее поле.
UPDATE "Report" SET "targetID" = "roomID" WHERE "targetID" IS NULL AND "roomID" IS NOT NULL;
-- SLA для незакрытых жалоб без срока: 24 часа от момента создания.
UPDATE "Report" SET "dueAt" = "createdAt" + INTERVAL '24 hours' WHERE "dueAt" IS NULL;

CREATE INDEX IF NOT EXISTS "Report_targetType_targetID_idx" ON "Report"("targetType", "targetID");
CREATE INDEX IF NOT EXISTS "Report_dueAt_idx" ON "Report"("dueAt");

-- Скрытие контента до разбора жалобы (автоскрытие с трёх независимых жалоб).
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "hidden"       BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Room"        ADD COLUMN IF NOT EXISTS "hidden"       BOOLEAN NOT NULL DEFAULT false;
-- Теневой бан: человек продолжает пользоваться приложением, но его
-- сообщения не видны остальным. Мягче полного бана и не провоцирует
-- на создание нового аккаунта.
ALTER TABLE "User"        ADD COLUMN IF NOT EXISTS "shadowbanned" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "ChatMessage_roomID_hidden_idx" ON "ChatMessage"("roomID", "hidden");

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Производительность: горячий запрос личных сообщений
-- ─────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS "DirectMessage_receiverID_createdAt_idx" ON "DirectMessage"("receiverID", "createdAt");
CREATE INDEX IF NOT EXISTS "DirectMessage_senderID_createdAt_idx"   ON "DirectMessage"("senderID", "createdAt");

-- ─────────────────────────────────────────────────────────────────────────
-- 3. GDPR: правила удаления
--
-- Cascade — данные принадлежат пользователю и должны исчезнуть вместе с ним.
-- SetNull — запись имеет самостоятельную ценность, но связь обезличивается.
--
-- Имена ограничений соответствуют соглашению Prisma: "Таблица_поле_fkey".
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE "Room" DROP CONSTRAINT IF EXISTS "Room_hostID_fkey";
ALTER TABLE "Room" ADD CONSTRAINT "Room_hostID_fkey"
  FOREIGN KEY ("hostID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ChatMessage" DROP CONSTRAINT IF EXISTS "ChatMessage_senderID_fkey";
ALTER TABLE "ChatMessage" ADD CONSTRAINT "ChatMessage_senderID_fkey"
  FOREIGN KEY ("senderID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "DirectMessage" DROP CONSTRAINT IF EXISTS "DirectMessage_senderID_fkey";
ALTER TABLE "DirectMessage" ADD CONSTRAINT "DirectMessage_senderID_fkey"
  FOREIGN KEY ("senderID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "DirectMessage" DROP CONSTRAINT IF EXISTS "DirectMessage_receiverID_fkey";
ALTER TABLE "DirectMessage" ADD CONSTRAINT "DirectMessage_receiverID_fkey"
  FOREIGN KEY ("receiverID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "FriendRequest" DROP CONSTRAINT IF EXISTS "FriendRequest_fromUserID_fkey";
ALTER TABLE "FriendRequest" ADD CONSTRAINT "FriendRequest_fromUserID_fkey"
  FOREIGN KEY ("fromUserID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "FriendRequest" DROP CONSTRAINT IF EXISTS "FriendRequest_toUserID_fkey";
ALTER TABLE "FriendRequest" ADD CONSTRAINT "FriendRequest_toUserID_fkey"
  FOREIGN KEY ("toUserID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Friendship" DROP CONSTRAINT IF EXISTS "Friendship_userID_fkey";
ALTER TABLE "Friendship" ADD CONSTRAINT "Friendship_userID_fkey"
  FOREIGN KEY ("userID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Friendship" DROP CONSTRAINT IF EXISTS "Friendship_friendID_fkey";
ALTER TABLE "Friendship" ADD CONSTRAINT "Friendship_friendID_fkey"
  FOREIGN KEY ("friendID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "WatchHistory" DROP CONSTRAINT IF EXISTS "WatchHistory_userID_fkey";
ALTER TABLE "WatchHistory" ADD CONSTRAINT "WatchHistory_userID_fkey"
  FOREIGN KEY ("userID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Subscription" DROP CONSTRAINT IF EXISTS "Subscription_userID_fkey";
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_userID_fkey"
  FOREIGN KEY ("userID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TransactionRecord" DROP CONSTRAINT IF EXISTS "TransactionRecord_userId_fkey";
ALTER TABLE "TransactionRecord" ADD CONSTRAINT "TransactionRecord_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "UserBlock" DROP CONSTRAINT IF EXISTS "UserBlock_blockerID_fkey";
ALTER TABLE "UserBlock" ADD CONSTRAINT "UserBlock_blockerID_fkey"
  FOREIGN KEY ("blockerID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "UserBlock" DROP CONSTRAINT IF EXISTS "UserBlock_blockedID_fkey";
ALTER TABLE "UserBlock" ADD CONSTRAINT "UserBlock_blockedID_fkey"
  FOREIGN KEY ("blockedID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Report" DROP CONSTRAINT IF EXISTS "Report_reporterID_fkey";
ALTER TABLE "Report" ADD CONSTRAINT "Report_reporterID_fkey"
  FOREIGN KEY ("reporterID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Referral" DROP CONSTRAINT IF EXISTS "Referral_referrerId_fkey";
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_referrerId_fkey"
  FOREIGN KEY ("referrerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Referral" DROP CONSTRAINT IF EXISTS "Referral_referredId_fkey";
ALTER TABLE "Referral" ADD CONSTRAINT "Referral_referredId_fkey"
  FOREIGN KEY ("referredId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Необязательные связи обезличиваются, а не удаляются вместе с записью.
ALTER TABLE "WatchHistory" DROP CONSTRAINT IF EXISTS "WatchHistory_roomID_fkey";
ALTER TABLE "WatchHistory" ADD CONSTRAINT "WatchHistory_roomID_fkey"
  FOREIGN KEY ("roomID") REFERENCES "Room"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Report" DROP CONSTRAINT IF EXISTS "Report_roomID_fkey";
ALTER TABLE "Report" ADD CONSTRAINT "Report_roomID_fkey"
  FOREIGN KEY ("roomID") REFERENCES "Room"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "PlaybackState" DROP CONSTRAINT IF EXISTS "PlaybackState_userID_fkey";
ALTER TABLE "PlaybackState" ADD CONSTRAINT "PlaybackState_userID_fkey"
  FOREIGN KEY ("userID") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
