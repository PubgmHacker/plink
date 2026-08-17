-- Add optional photo attachment storage for watch-room chat messages.
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaType" TEXT;
ALTER TABLE "ChatMessage" ADD COLUMN IF NOT EXISTS "mediaData" TEXT;
