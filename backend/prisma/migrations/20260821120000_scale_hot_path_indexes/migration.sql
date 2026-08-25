-- Hot-path indexes for 10k+ concurrent users.
--
-- The four Room indexes have existed in schema.prisma since stabilize_v2 but no
-- migration ever created them — `prisma migrate deploy` replays only checked-in
-- SQL and never reads @@index from the schema, so production has been running
-- discovery/"my rooms" queries on seq scans. Names match Prisma's derived names
-- exactly so `prisma migrate diff` reports no drift.
--
-- No CONCURRENTLY: migrate deploy wraps each migration in a transaction and
-- CONCURRENTLY cannot run inside one. These tables are small enough today that
-- a blocking build is fine; revisit if a table passes ~10M rows.

-- Room: discovery (isActive+privacy), "my rooms" (hostID), media dedupe
CREATE INDEX IF NOT EXISTS "Room_isActive_createdAt_idx" ON "Room"("isActive", "createdAt");
CREATE INDEX IF NOT EXISTS "Room_privacy_isActive_idx" ON "Room"("privacy", "isActive");
CREATE INDEX IF NOT EXISTS "Room_hostID_idx" ON "Room"("hostID");
CREATE INDEX IF NOT EXISTS "Room_mediaItem_idx" ON "Room"("mediaItem");

-- WatchHistory: fastest-growing table, had zero indexes. First serves profile
-- reads (findMany orderBy watchedAt DESC) and the count; second serves the
-- dedupe findFirst on every room leave (userID+roomID+watchedAt >= now-1h),
-- which otherwise full-scans the heap on every MISS — the common case.
CREATE INDEX IF NOT EXISTS "WatchHistory_userID_watchedAt_idx" ON "WatchHistory"("userID", "watchedAt");
CREATE INDEX IF NOT EXISTS "WatchHistory_userID_roomID_watchedAt_idx" ON "WatchHistory"("userID", "roomID", "watchedAt");

-- Friendship: GET /api/friends filters friendID = me; the only existing indexes
-- lead with userID, so this was O(total friendships in the product) per call.
CREATE INDEX IF NOT EXISTS "Friendship_friendID_idx" ON "Friendship"("friendID");

-- FriendRequest: incoming-requests list filters toUserID + status; the only
-- existing index is unique(fromUserID, toUserID).
CREATE INDEX IF NOT EXISTS "FriendRequest_toUserID_status_idx" ON "FriendRequest"("toUserID", "status");
