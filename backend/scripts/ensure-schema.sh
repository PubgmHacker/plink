#!/bin/sh
# Idempotent schema patches when prisma migrate deploy is blocked (P3009).
set -e

echo "==== ensure-schema: avatarData column ===="
npx prisma db execute --stdin <<'SQL'
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "avatarData" TEXT;
SQL
echo "==== ensure-schema done ===="