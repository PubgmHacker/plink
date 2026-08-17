-- Plink V5 migration: appearance persistence + GDPR scheduled deletion
-- Source: PLINK_MASTER_PLAN_10_OF_10.md Phase 4
--
-- Adds 3 nullable columns to existing tables. All are nullable so the
-- migration is fully backwards-compatible — old clients keep working,
-- null values fall back to client defaults.
--
-- After applying, run `npx prisma generate` to refresh the TypeScript client.

-- User.appearancePrefs: JSON-stringified { appThemeID, bubbleStyleID, emojiPackID }
ALTER TABLE "User" ADD COLUMN "appearancePrefs" TEXT;

-- User.scheduledForDeletionAt: GDPR 14-day grace period
ALTER TABLE "User" ADD COLUMN "scheduledForDeletionAt" TIMESTAMP(3);

-- Room.appearance: JSON-stringified RoomAppearance { themeId, themeRevision, intensity, motionEnabled }
ALTER TABLE "Room" ADD COLUMN "appearance" TEXT;
