# Plink Backend

## Быстрый старт на Railway

1. Создайте новый проект на Railway
2. Add → Database → PostgreSQL
3. Add → Empty Service → (этот репозиторий)
4. Variables:
   - DATABASE_URL = (из PostgreSQL, Railway даст автоматически)
   - JWT_SECRET = любой случайный ключ (например: plink-secret-2026)
   - CORS_ORIGIN = *
5. Deploy

После деплоя:

- npx prisma db push (через Railway CLI или console)
- API будет на https://ваш-домен.up.railway.app/api
- WebSocket на wss://ваш-домен.up.railway.app/ws

## CI и тесты

- CI: `.github/workflows/ci.yml` (корень монорепо) — job `backend`: redis:7 как service, `npm ci` → `prisma generate` → `tsc --noEmit` → `vitest run` с `REDIS_URL`.
- Локально: `npm test` (watch) или `npx vitest run`; без Redis интеграционные тесты скипаются, и в конце прогона печатается громкое предупреждение с их количеством.
- Полный интеграционный прогон: `REDIS_URL="redis://localhost:6380" npm run test:integration` — скрипт падает, если `REDIS_URL` не задан.
- Типы: `npx tsc --noEmit` обязан давать 0 ошибок перед любым коммитом.
- iOS-job в CI пока заглушка (репозиторий на GitHub устарел, macos-runner не настроен).
