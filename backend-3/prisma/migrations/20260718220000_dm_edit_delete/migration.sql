-- Telegram-style message edit + per-user delete
ALTER TABLE "DirectMessage" ADD COLUMN "editedAt" TIMESTAMP(3);
ALTER TABLE "DirectMessage" ADD COLUMN "deletedForIDs" TEXT[] NOT NULL DEFAULT '{}';
