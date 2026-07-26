# Патч openapi до 1.7.0

Баг №10 из аудита: спецификация застряла на 1.6.0, приложение ушло вперᄅд.
Описание, которому нельзя верить, хуже, чем отсутствие описания.

## 1. Версия

```yaml
info:
  title: Plink API
  version: 1.7.0
```

## 2. Новые пути

```yaml
paths:
  /api/realtime/time:
    get:
      summary: Синхронизация часов (NTP-подобная)
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                required: [serverTime, t1, t2]
                properties:
                  serverTime: { type: string, format: date-time }
                  t0: { type: integer, nullable: true }
                  t1: { type: integer, description: Момент приᄅма запроса, мс }
                  t2: { type: integer, description: Момент отправки ответа, мс }

  /api/moderation/report:
    post:
      summary: Пожаловаться на пользователя, сообщение или комнату
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [targetType, targetId, reason]
              properties:
                targetType: { type: string, enum: [user, message, room] }
                targetId: { type: string }
                reason:
                  type: string
                  enum: [spam, harassment, hate, sexual, violence, illegal, copyright, other]
                comment: { type: string, nullable: true }

  /api/moderation/block:
    post: { summary: Заблокировать пользователя }
  /api/moderation/block/{userId}:
    delete: { summary: Разблокировать }
  /api/moderation/blocked:
    get: { summary: Список заблокированных }
  /api/moderation/queue:
    get: { summary: Очередь модератора, только для isModerator }
  /api/moderation/queue/{id}/resolve:
    post: { summary: Решение по жалобе (dismiss, hide, ban) }

  /api/users/me:
    delete: { summary: Удалить аккаунт, грейс-период 7 дней }
  /api/users/me/restore:
    post: { summary: Восстановить аккаунт в грейс-период }
  /api/users/me/export:
    get: { summary: Экспорт данных, формат plink-export-v1 }

  /api/subscription/verify:
    post: { summary: Проверка транзакции StoreKit 2 }
  /api/subscription/status:
    get: { summary: Текущий статус Plink+ }
  /api/subscription/apple-notifications:
    post: { summary: App Store Server Notifications V2 }

  /api/push/register:
    post: { summary: Зарегистрировать APNs-токен }
  /api/push/preferences:
    patch: { summary: Настройки уведомлений }

  /.well-known/apple-app-site-association:
    get: { summary: Universal Links, без префикса /api }
```

## 3. Изменᄅнное поведение старых путей

- `POST /api/ai/stream` — теперь шлᄅт heartbeat-комментарии `: ping` каждые 15 секунд.
  Клиенты обязаны игнорировать строки, начинающиеся с `:`.
- Ошибки потока приходят как `{ "error": "upstream_failed" | "stream_failed", "message": "…" }`.
- Лимиты считаются по userId, а не по IP.
