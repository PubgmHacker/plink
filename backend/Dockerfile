# Railway builds this monorepo from its repository root. Paths are therefore
# explicit instead of assuming backend is already the build context.
FROM node:20-slim AS builder

# OpenSSL required by Prisma.
RUN apt-get update -y && apt-get install -y \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY backend/package*.json ./
# Install ALL deps (including dev) — needed for tsc build.
RUN npm ci
COPY backend/ .

# Prove which sources are in the image (helps debug stale Railway logs)
RUN node -e "const p=require('./package.json'); console.log('[builder] plink-server@'+p.version+' build='+p.scripts.build)"

RUN npx prisma generate

# Build TypeScript to dist/ (package.json: prisma generate && tsc)
RUN npm run build

# Fail the image if invites never[] / profile typing regressed
RUN test -f dist/routes/messages.js && test -f dist/routes/profile.js && \
    node -e "console.log('[builder] tsc OK — dist/routes present')"

# ─── Runtime stage ────────────────────────────────────────────────────
FROM node:20-slim

# yt-dlp is pinned to an exact release. An unpinned download from
# releases/latest lets any deploy pick up a different binary — including one
# whose extractors have regressed — with no change on our side.
# To update: pick a tag at https://github.com/yt-dlp/yt-dlp/releases, bump
# YTDLP_VERSION below, and exercise /api/media/extract on staging first.
ARG YTDLP_VERSION=2026.07.04
RUN apt-get update -y && apt-get install -y \
    openssl \
    python3 \
    curl \
    ca-certificates \
    && curl -fL "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp" -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp \
    && yt-dlp --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only production deps + built dist/
COPY backend/package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
# Self-hosted webfonts served by routes/web.ts (strict CSP forbids font CDNs).
COPY --from=builder /app/assets ./assets
COPY --from=builder /app/start.sh ./start.sh
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
# certs/ must be present at runtime: the JWS verifier resolves the Apple root
# as ./certs/AppleRootCA-G3.cer. Without it, receipt verification rejects
# genuine App Store receipts as well as forged ones — and the self-check does
# not catch that, because it only asserts that a forgery is rejected.
COPY --from=builder /app/certs ./certs

# Production dependencies include the pinned Prisma CLI used by start.sh.
# Keeping it in the image avoids an unpinned network download during boot.
RUN test -x node_modules/.bin/prisma && chmod +x start.sh

# Run as the unprivileged `node` user the base image already ships with.
RUN chown -R node:node /app
USER node

EXPOSE 8080

# Container-level liveness for docker/compose hosts. Railway ignores this and gates
# promotion with railway.json (healthcheckPath /health/ready) instead.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/health/live" || exit 1

# start.sh runs the pinned migration CLI and then node dist/server.js
CMD ["./start.sh"]
