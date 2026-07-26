-- Telegram-style DM features: replies, forwards, pins
ALTER TABLE "DirectMessage" ADD COLUMN "replyToID" TEXT;
ALTER TABLE "DirectMessage" ADD COLUMN "forwardedFromID" TEXT;
ALTER TABLE "DirectMessage" ADD COLUMN "forwardedFromName" TEXT;
ALTER TABLE "DirectMessage" ADD CONSTRAINT "DirectMessage_replyToID_fkey" FOREIGN KEY ("replyToID") REFERENCES "DirectMessage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "DirectMessagePin" (
    "id" TEXT NOT NULL,
    "ownerID" TEXT NOT NULL,
    "peerID" TEXT NOT NULL,
    "messageID" TEXT NOT NULL,
    "pinnedByID" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "DirectMessagePin_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "DirectMessagePin_ownerID_peerID_messageID_key" ON "DirectMessagePin"("ownerID", "peerID", "messageID");
CREATE INDEX "DirectMessagePin_ownerID_peerID_idx" ON "DirectMessagePin"("ownerID", "peerID");

ALTER TABLE "DirectMessagePin" ADD CONSTRAINT "DirectMessagePin_ownerID_fkey" FOREIGN KEY ("ownerID") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "DirectMessagePin" ADD CONSTRAINT "DirectMessagePin_messageID_fkey" FOREIGN KEY ("messageID") REFERENCES "DirectMessage"("id") ON DELETE CASCADE ON UPDATE CASCADE;
