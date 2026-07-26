-- Avatar revision timestamp (friends cache-bust without using polluted updatedAt)
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "avatarUpdatedAt" TIMESTAMP(3);

-- Seed once for users who already have an avatar so clients pick up ?v= immediately
UPDATE "User"
SET "avatarUpdatedAt" = COALESCE("updatedAt", NOW())
WHERE "avatarData" IS NOT NULL
  AND "avatarUpdatedAt" IS NULL;
