-- Telegram-style reactions on direct messages
CREATE TABLE IF NOT EXISTS "DirectMessageReaction" (
    "id" TEXT NOT NULL,
    "messageID" TEXT NOT NULL,
    "userID" TEXT NOT NULL,
    "emoji" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "DirectMessageReaction_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "DirectMessageReaction_messageID_userID_key"
  ON "DirectMessageReaction"("messageID", "userID");

CREATE INDEX IF NOT EXISTS "DirectMessageReaction_messageID_idx"
  ON "DirectMessageReaction"("messageID");

DO $$ BEGIN
  ALTER TABLE "DirectMessageReaction"
    ADD CONSTRAINT "DirectMessageReaction_messageID_fkey"
    FOREIGN KEY ("messageID") REFERENCES "DirectMessage"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "DirectMessageReaction"
    ADD CONSTRAINT "DirectMessageReaction_userID_fkey"
    FOREIGN KEY ("userID") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
