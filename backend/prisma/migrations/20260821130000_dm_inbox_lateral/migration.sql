-- DM inbox (GET /messages/unread) rewritten from full-history CTE to
-- friend-list LATERAL probes. Two new indexes carry it:
--
--   (senderID, receiverID, createdAt) — last-message-in-thread probe:
--     one index descent + LIMIT 1 per direction per friend. Supersedes the
--     old (senderID, receiverID) prefix index, which is dropped below —
--     keeping both would only tax every DM insert.
--
--   (receiverID, isRead, senderID) — the unread aggregate:
--     one range scan sized by the user's unread count (small by definition),
--     grouped by sender straight out of the index.
--
-- Order matters: create replacements first, drop the redundant prefix last,
-- so there is no window where pair probes have no index at all.
-- No CONCURRENTLY: migrate deploy wraps migrations in a transaction.
-- Names match Prisma's derived names so `prisma migrate diff` stays clean.

CREATE INDEX IF NOT EXISTS "DirectMessage_senderID_receiverID_createdAt_idx"
  ON "DirectMessage"("senderID", "receiverID", "createdAt");

CREATE INDEX IF NOT EXISTS "DirectMessage_receiverID_isRead_senderID_idx"
  ON "DirectMessage"("receiverID", "isRead", "senderID");

DROP INDEX IF EXISTS "DirectMessage_senderID_receiverID_idx";
