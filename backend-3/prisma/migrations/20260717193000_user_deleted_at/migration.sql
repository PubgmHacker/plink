-- Telegram-style soft delete: keep user id for chats/friends, strip PII
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMP(3);
CREATE INDEX IF NOT EXISTS "User_deletedAt_idx" ON "User"("deletedAt");
