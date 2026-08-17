-- Telegram-style chat pins (per friendship direction: userID pins friendID)
ALTER TABLE "Friendship" ADD COLUMN IF NOT EXISTS "isPinned" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Friendship" ADD COLUMN IF NOT EXISTS "pinOrder" INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS "Friendship_userID_isPinned_pinOrder_idx"
  ON "Friendship"("userID", "isPinned", "pinOrder");
