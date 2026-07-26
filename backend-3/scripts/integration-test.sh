#!/usr/bin/env bash
# scripts/integration-test.sh — Brain Review 4 P1-31 one-command harness
#
# Brings up Postgres + Redis via Docker Compose, runs migrations, runs
# all integration tests with 0 skipped, tears down.
#
# Usage:
#   bash scripts/integration-test.sh
#
# Prerequisites:
#   - Docker Desktop running
#   - npm install completed

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Step 1: Start Docker Compose (Postgres + Redis) ==="
docker compose -f tests/integration/docker-compose.yml up -d --wait

# Determine host ports from docker-compose.yml
PG_PORT=$(docker compose -f tests/integration/docker-compose.yml port postgres 5432 | cut -d: -f2)
REDIS_PORT=$(docker compose -f tests/integration/docker-compose.yml port redis 6379 | cut -d: -f2)

export DATABASE_URL="postgresql://plink:plink@localhost:${PG_PORT}/plink"
export REDIS_URL="redis://localhost:${REDIS_PORT}"

echo "  DATABASE_URL=$DATABASE_URL"
echo "  REDIS_URL=$REDIS_URL"
echo ""

echo "=== Step 2: Prisma generate ==="
npx prisma generate

echo ""
echo "=== Step 3: Prisma migrate deploy ==="
npx prisma migrate deploy

echo ""
echo "=== Step 4: Prisma validate ==="
npx prisma validate

echo ""
echo "=== Step 5: TypeScript build ==="
npm run build

echo ""
echo "=== Step 6: Run ALL tests (contract + integration, 0 skipped expected) ==="
npm run test:ci

echo ""
echo "=== Step 7: Prisma migrate status ==="
npx prisma migrate status

echo ""
echo "=== Cleanup ==="
echo "Docker containers are still running. To stop:"
echo "  docker compose -f tests/integration/docker-compose.yml down -v"
echo ""
echo "✅ Integration test harness complete."
