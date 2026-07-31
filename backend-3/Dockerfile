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

# Аудит 26.07.2026 (7.5): yt-dlp запинен по версии — раньше тянулся releases/latest,
# и каждый деплой мог молча получить другой бинарь (или сломанный экстрактор).
# Как обновлять: выбрать тег на https://github.com/yt-dlp/yt-dlp/releases,
# поменять YTDLP_VERSION ниже и проверить /api/media/extract на стейдже.
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
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
# Self-hosted webfonts served by routes/web.ts (strict CSP forbids font CDNs).
COPY --from=builder /app/assets ./assets
COPY --from=builder /app/start.sh ./start.sh
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
# Аудит 26.07.2026 P0: без certs/ в рантайме верификация покупок отклоняла бы
# и НАСТОЯЩИЕ чеки Apple — jose-config ищет ./certs/AppleRootCA-G3.cer.
# Самопроверка при этом зеленела: она проверяет только отклонение подделки.
COPY --from=builder /app/certs ./certs

# Production dependencies include the pinned Prisma CLI used by start.sh.
# Keeping it in the image avoids an unpinned network download during boot.
RUN test -x node_modules/.bin/prisma && chmod +x start.sh

# Аудит 26.07.2026: не под root — базовый node-образ содержит пользователя node.
RUN chown -R node:node /app
USER node

EXPOSE 8080

# start.sh runs the pinned migration CLI and then node dist/server.js
CMD ["./start.sh"]
