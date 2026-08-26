-- Настройки беседы как в Telegram: аватар, описание, права участников
ALTER TABLE "GroupChat" ADD COLUMN "description" TEXT;
ALTER TABLE "GroupChat" ADD COLUMN "avatarData" TEXT;
ALTER TABLE "GroupChat" ADD COLUMN "avatarUpdatedAt" TIMESTAMP(3);
ALTER TABLE "GroupChat" ADD COLUMN "membersCanInvite" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "GroupChat" ADD COLUMN "membersCanSendMedia" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "GroupChat" ADD COLUMN "membersCanChangeInfo" BOOLEAN NOT NULL DEFAULT false;
