FROM node:20-slim AS builder

# OpenSSL required by Prisma.
RUN apt-get update -y && apt-get install -y \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
# Install ALL deps (including dev) — needed for tsc build.
RUN npm ci || npm install
COPY . .

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

RUN apt-get update -y && apt-get install -y \
    openssl \
    python3 \
    curl \
    ca-certificates \
    && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp \
    && yt-dlp --version \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only production deps + built dist/
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/start.sh ./start.sh
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

RUN chmod +x start.sh

EXPOSE 8080

# start.sh runs prisma generate + migrate deploy + node dist/server.js
CMD ["./start.sh"]
