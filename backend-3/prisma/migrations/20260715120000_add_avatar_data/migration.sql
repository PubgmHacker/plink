-- Avatar base64 storage (Railway ephemeral filesystem — no disk persistence)
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "avatarData" TEXT;