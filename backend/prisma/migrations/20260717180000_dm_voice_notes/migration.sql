-- Friend DM voice notes (real audio, not placeholder text)
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "mediaType" TEXT;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "mediaData" TEXT;
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "mediaDurationSec" DOUBLE PRECISION;
