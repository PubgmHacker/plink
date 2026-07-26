#!/bin/sh
# start.sh — Railway/Docker startup script (v3 stream-extractor racer)
#
# v3 changes:
#   - Keep the self-hosted yt-dlp extractor fresh at startup and daily while
#     the container is alive. Extractor failures must not prevent API boot.
#   - Use prisma migrate deploy (NOT db push) — proper migration history
#   - Build TypeScript to dist/ in Docker builder stage (NOT at runtime)
set -e

update_ytdlp() {
  if command -v yt-dlp >/dev/null 2>&1; then
    echo "==== yt-dlp update: starting ===="
    yt-dlp -U || echo "WARN: yt-dlp update failed; continuing with bundled version"
    echo "==== yt-dlp update: done ($(yt-dlp --version 2>/dev/null || echo unknown)) ===="
  else
    echo "WARN: yt-dlp binary not found; yt-dlp extractor will fail"
  fi
}

update_ytdlp
(
  while true; do
    sleep 86400
    update_ytdlp
  done
) &

echo "==== Step 1/2: prisma generate ===="
npx prisma generate
echo "==== Step 1/2 done ===="

echo "==== Step 2/2: prisma migrate deploy + start ===="
# Production-safe: applies pending migrations only, does NOT create new ones.
# If a prior migration failed (P3009), resolve and continue so the service stays up.
if ! npx prisma migrate deploy < /dev/null; then
  echo "WARN: migrate deploy failed — attempting resolve + idempotent schema patch"
  npx prisma migrate resolve --applied 20260712000000_billing_admin_v2 2>/dev/null || true
  npx prisma migrate deploy < /dev/null || true
  sh ./scripts/ensure-schema.sh || true
fi
echo "==== Step 2/2 done ===="

export NODE_ENV="${NODE_ENV:-production}"
exec node dist/server.js
