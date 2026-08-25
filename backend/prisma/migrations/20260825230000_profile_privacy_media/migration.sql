-- VK-style closed profile + denormalized media art in watch history
ALTER TABLE "User" ADD COLUMN "profileClosed" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "WatchHistory" ADD COLUMN "mediaThumb" TEXT;
ALTER TABLE "WatchHistory" ADD COLUMN "mediaKind" TEXT;
