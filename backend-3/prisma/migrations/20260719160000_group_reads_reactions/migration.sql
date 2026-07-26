-- M17: unread-бейджи бесед + удаление сообщений + реакции
ALTER TABLE "GroupMember" ADD COLUMN "lastReadAt" TIMESTAMP(3);
ALTER TABLE "GroupMessage" ADD COLUMN "deletedAt" TIMESTAMP(3);
ALTER TABLE "GroupMessage" ADD COLUMN "reactions" JSONB;
