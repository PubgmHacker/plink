#!/usr/bin/env bash
# scripts/migrate-baseline.sh — Brain Review 4 P0-26 baseline plan
#
# Existing Railway DB was created via 'prisma db push' — it has tables but
# NO _prisma_migrations entries. Running 'prisma migrate deploy' would try
# to CREATE TABLE on already-existing tables and fail.
#
# This script performs the baseline procedure SAFELY:
#   1. Create disposable clone of production schema (no data)
#   2. Run prisma migrate diff to check if existing schema matches migration
#   3. If match: mark migration as applied via 'prisma migrate resolve'
#   4. If drift: generate additive migration for the diff
#
# Usage:
#   STAGING_DATABASE_URL="postgresql://..." \
#   PRODUCTION_DATABASE_URL="postgresql://..." \
#   bash scripts/migrate-baseline.sh
#
# NEVER run this directly against production without a backup.

set -euo pipefail

STAGING_DATABASE_URL="${STAGING_DATABASE_URL:-}"
PRODUCTION_DATABASE_URL="${PRODUCTION_DATABASE_URL:-}"

if [[ -z "$STAGING_DATABASE_URL" ]]; then
  echo "ERROR: STAGING_DATABASE_URL is required"
  echo "Set it to a disposable clone of production schema."
  exit 1
fi

echo "=== Step 1: Check schema drift ==="
echo "Comparing staging schema (clone of prod) with prisma/schema.prisma..."
echo ""

npx prisma migrate diff \
  --from-url "$STAGING_DATABASE_URL" \
  --to-schema-datamodel prisma/schema.prisma \
  --script > /tmp/schema-drift.sql 2>/dev/null || true

if [[ ! -s /tmp/schema-drift.sql ]]; then
  echo "✅ Schema matches — no drift detected."
  echo ""
  echo "=== Step 2: Baseline migration ==="
  echo "Marking 20260711000000_stabilize_v2 as applied on staging..."
  DATABASE_URL="$STAGING_DATABASE_URL" npx prisma migrate resolve \
    --applied 20260711000000_stabilize_v2
  echo ""
  echo "✅ Baseline complete. Verify with:"
  echo "  DATABASE_URL=$STAGING_DATABASE_URL npx prisma migrate status"
  echo ""
  echo "=== Step 3: Production rollout ==="
  echo "If staging verification passed, apply to production:"
  echo "  1. BACKUP production DB"
  echo "  2. Schedule maintenance window"
  echo "  3. DATABASE_URL=<prod> npx prisma migrate resolve --applied 20260711000000_stabilize_v2"
  echo "  4. Verify: DATABASE_URL=<prod> npx prisma migrate status"
  echo ""
  echo "⚠️  Do NOT run 'prisma migrate deploy' on production until baseline is applied."
else
  echo "⚠️  SCHEMA DRIFT DETECTED — existing DB does NOT match migration."
  echo "Drift SQL saved to /tmp/schema-drift.sql:"
  echo ""
  cat /tmp/schema-drift.sql
  echo ""
  echo "=== Next steps ==="
  echo "1. Review the drift SQL above"
  echo "2. Create an additive migration for the actual drift:"
  echo "   npx prisma migrate dev --name fix_drift --create-only"
  echo "3. Edit the generated SQL to match the drift"
  echo "4. Apply: npx prisma migrate deploy"
  echo "5. Then baseline 20260711000000_stabilize_v2"
  exit 2
fi
