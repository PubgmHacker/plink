# Plink M39 — интеграция backend

## 1. Файлы

| Файл | Действие | Зачем |
| --- | --- | --- |
| `src/routes/web.ts` | Заменить | Закрыта XSS в лендингах, добавлены AASA и og:image |
| `src/routes/aiStream.ts` | Заменить | AbortController, heartbeat, rate limit по userId |
| `src/routes/moderation.ts` | Добавить | Жалобы, блок-лист, очередь модератора |
| `src/routes/account.ts` | Добавить | Удаление аккаунта (5.1.1(v)), экспорт данных |
| `src/routes/subscription.ts` | Добавить | Проверка StoreKit 2, App Store Server Notifications V2 |
| `src/routes/push.ts` | Добавить | APNs HTTP/2 token-based |
| `src/routes/timeSync.ts` | Заменить | `/realtime/time` с точками t1/t2 для RTT |
| `prisma/migrations_m39.prisma` | Слить в schema | Новые модели и поля |

## 2. Регистрация роутов

```ts
import { webRoutes } from './routes/web'
import { aiStreamRoutes } from './routes/aiStream'
import { moderationRoutes } from './routes/moderation'
import { accountRoutes } from './routes/account'
import { subscriptionRoutes } from './routes/subscription'
import { pushRoutes } from './routes/push'
import { timeSyncRoutes } from './routes/timeSync'

// ВАЖНО: webRoutes регистрируются БЕЗ префикса — Apple требует AASA в корне домена.
fastify.register(webRoutes)

fastify.register(aiStreamRoutes, { prefix: '/api' })
fastify.register(moderationRoutes, { prefix: '/api' })
fastify.register(accountRoutes, { prefix: '/api' })
fastify.register(subscriptionRoutes, { prefix: '/api' })
fastify.register(pushRoutes, { prefix: '/api' })
fastify.register(timeSyncRoutes, { prefix: '/api' })
```

## 3. Переменные окружения

```
PUBLIC_ORIGIN=https://plink.app
APP_STORE_URL=https://apps.apple.com/app/id0000000000
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_BUNDLE_ID=com.plink.app
APPLE_ROOT_CA_PEM="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
APNS_KEY_ID=XXXXXXXXXX
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
APNS_ENV=sandbox   # переключить на production перед релизом
```

Без `APPLE_ROOT_CA_PEM` проверка покупок будет всегда отклоняться — это намеренно.
Лучше не продавать вообще, чем раздавать Plink+ по поддельным чекам.

## 4. Миграции

```bash
# слейте содержимое prisma/migrations_m39.prisma в prisma/schema.prisma
npx prisma migrate dev --name m39_moderation_billing_push
npx prisma generate
```

## 5. Проверки после деплоя

```bash
BASE=https://plink-production.up.railway.app

# 1. На лендингах НЕ ДОЛЖНО быть ни одного <script>
curl -s $BASE/r/ABCD | grep -c '<script'      # ожидаем 0

# 2. Невалидный username — 404, а не 500 и не отражённый HTML
curl -s -o /dev/null -w '%{http_code}\n' "$BASE/u/test%5C"   # ожидаем 404

# 3. Universal Links
curl -s $BASE/.well-known/apple-app-site-association | head

# 4. Синхронизация времени отдаёт t1 и t2
curl -s $BASE/api/realtime/time

# 5. SSE шлёт heartbeat и закрывается при обрыве клиента
curl -N -X POST $BASE/api/ai/stream -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"привет"}]}'
```

## 6. Фоновая задача

Раз в сутки вызывайте `purgeExpiredAccounts()` из `routes/account.ts` —
она физически удаляет аккаунты, у которых истёк грейс-период 7 дней.

## 7. Чего здесь сознательно НЕТ

- Код не компилировался и не запускался — в песочнице нет ни сети, ни базы.
  Обязательно прогоните `npx tsc --noEmit` перед деплоем.
- Имена полей Prisma (`friendship`, `roomMember`, `groupMember`, `session`, `mediaTitle`)
  взяты из текущей схемы M38. Если в вашей схеме они называются иначе — поправьте.
