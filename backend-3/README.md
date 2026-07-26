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
