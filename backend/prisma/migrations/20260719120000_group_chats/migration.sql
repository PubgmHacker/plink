-- M16: group chats (беседы) — Telegram-style groups inside Plink
CREATE TABLE "GroupChat" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "ownerID" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "GroupChat_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GroupMember" (
    "id" TEXT NOT NULL,
    "groupID" TEXT NOT NULL,
    "userID" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'member',
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "GroupMember_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "GroupMessage" (
    "id" TEXT NOT NULL,
    "groupID" TEXT NOT NULL,
    "senderID" TEXT NOT NULL,
    "senderName" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "mediaType" TEXT,
    "mediaData" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "GroupMessage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "GroupMember_groupID_userID_key" ON "GroupMember"("groupID", "userID");
CREATE INDEX "GroupMember_userID_idx" ON "GroupMember"("userID");
CREATE INDEX "GroupMessage_groupID_createdAt_idx" ON "GroupMessage"("groupID", "createdAt");

ALTER TABLE "GroupMember" ADD CONSTRAINT "GroupMember_groupID_fkey" FOREIGN KEY ("groupID") REFERENCES "GroupChat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "GroupMessage" ADD CONSTRAINT "GroupMessage_groupID_fkey" FOREIGN KEY ("groupID") REFERENCES "GroupChat"("id") ON DELETE CASCADE ON UPDATE CASCADE;
