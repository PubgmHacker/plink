-- Аудит 07.08.2026 (находка №15): дрейф схемы AIModerationAudit.
--
-- Модель есть в schema.prisma (стр. 438) и код в неё ПИШЕТ:
--   src/moderation/autoMod.ts:175         prisma.aIModerationAudit.create()
--   src/services/moderation/moderationAudit.ts:11
-- Вызовы идут из realtime/messageRouter.ts, routes/messages.ts, routes/groups.ts.
--
-- Но миграции, создающей таблицу, не было ни в одной из 17. На свежей БД
-- (prisma migrate deploy → CI, стейдж, новый Railway) create() падал, ошибку
-- глотал try/catch и писал '[autoMod] audit failed' — аудиты модерации молча
-- терялись. На текущем проде таблица, вероятно, есть: та база создавалась
-- через `prisma db push` (см. scripts/migrate-baseline.sh).
--
-- Поэтому IF NOT EXISTS везде: миграция обязана быть безопасной И на
-- db push-базе (таблица уже есть → no-op), И на чистой (создаст).

CREATE TABLE IF NOT EXISTS "AIModerationAudit" (
    "id"            TEXT             NOT NULL,
    "roomId"        TEXT             NOT NULL,
    "messageId"     TEXT             NOT NULL,
    "subjectUserId" TEXT             NOT NULL,
    "action"        TEXT             NOT NULL,
    "reasonCode"    TEXT             NOT NULL,
    "confidence"    DOUBLE PRECISION,
    "policyVersion" TEXT             NOT NULL,
    "modelVersion"  TEXT,
    "evidenceHash"  TEXT             NOT NULL,
    "reversible"    BOOLEAN          NOT NULL DEFAULT true,
    "reviewedBy"    TEXT,
    "reviewedAt"    TIMESTAMP(3),
    "createdAt"     TIMESTAMP(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AIModerationAudit_pkey" PRIMARY KEY ("id")
);

-- Индексы под два реальных запроса: разбор инцидентов по комнате и
-- история решений по пользователю (оба — по свежести).
CREATE INDEX IF NOT EXISTS "AIModerationAudit_roomId_createdAt_idx"
    ON "AIModerationAudit" ("roomId", "createdAt");

CREATE INDEX IF NOT EXISTS "AIModerationAudit_subjectUserId_createdAt_idx"
    ON "AIModerationAudit" ("subjectUserId", "createdAt");
