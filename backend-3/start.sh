#!/bin/sh
# Railway/Docker startup: apply the checked-in migration history, then boot.
# Migration failures are fatal. Never mark a failed migration as applied: doing
# so starts the API against a schema that does not match Prisma Client.
set -eu

echo "==== prisma migrate deploy ===="
./node_modules/.bin/prisma migrate deploy < /dev/null
echo "==== migrations complete ===="

export NODE_ENV="${NODE_ENV:-production}"
exec node dist/server.js
