-- Аудит 26.07.2026 (P2, be-billing): идемпотентность покупок и вебхуков.
--
-- Проверено перед применением на проде 26.07.2026: в "Subscription" 0 строк,
-- поэтому шаги 1-2 — no-op. Они оставлены, потому что миграция выполняется
-- автоматически при деплое (start.sh → prisma migrate deploy) и должна быть
-- безопасной на любой базе, где дубликаты уже успели накопиться.

-- ── 1. Развести дубликаты Subscription по originalTransactionId ────────────
--    Причина дублей: сломанный upsert в billing.ts (create без id) создавал
--    новую активную строку на каждый verify/renew. Строки НЕ удаляем — у
--    проигравших гасим isActive и делаем значение уникальным с сохранением
--    следа, чтобы не потерять историю платежей.
WITH ranked AS (
  SELECT "id",
         ROW_NUMBER() OVER (
           PARTITION BY "originalTransactionId"
           ORDER BY COALESCE("lastVerifiedAt", "createdAt") DESC, "createdAt" DESC
         ) AS rn
  FROM "Subscription"
  WHERE "originalTransactionId" IS NOT NULL
)
UPDATE "Subscription" s
SET "isActive" = false,
    "originalTransactionId" = s."originalTransactionId" || ':dup:' || s."id"
FROM ranked r
WHERE s."id" = r."id" AND r.rn > 1;

-- ── 2. Каноническая строка Apple-подписки: id = originalTransactionId ──────
--    billing.ts ключует upsert по первичному ключу, поэтому легаси-строка со
--    случайным uuid после добавления @unique конфликтовала бы с новым create
--    (P2002 на verify). Веб-платежи ЮKassa ('yookassa:<paymentId>') не трогаем.
--    Внешних ключей на Subscription.id в схеме нет — смена id безопасна.
UPDATE "Subscription" s
SET "id" = s."originalTransactionId"
WHERE s."originalTransactionId" IS NOT NULL
  AND s."originalTransactionId" NOT LIKE 'yookassa:%'
  AND s."originalTransactionId" NOT LIKE '%:dup:%'
  AND s."id" <> s."originalTransactionId"
  AND NOT EXISTS (SELECT 1 FROM "Subscription" o WHERE o."id" = s."originalTransactionId");

-- ── 3. Уникальность originalTransactionId ─────────────────────────────────
--    NULL'ы в Postgres друг с другом не конфликтуют, поэтому комплиментарные
--    и демо-подписки без originalTransactionId продолжают жить.
DROP INDEX IF EXISTS "Subscription_originalTransactionId_idx";
CREATE UNIQUE INDEX IF NOT EXISTS "Subscription_originalTransactionId_key"
  ON "Subscription"("originalTransactionId");

-- ── 4. Обработанные уведомления Apple (дедупликация доставок) ─────────────
CREATE TABLE IF NOT EXISTS "AppleNotification" (
  "notificationUUID"      TEXT         NOT NULL,
  "notificationType"      TEXT         NOT NULL,
  "originalTransactionId" TEXT,
  "signedDate"            TIMESTAMP(3),
  "processedAt"           TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AppleNotification_pkey" PRIMARY KEY ("notificationUUID")
);
CREATE INDEX IF NOT EXISTS "AppleNotification_originalTransactionId_idx"
  ON "AppleNotification"("originalTransactionId");
