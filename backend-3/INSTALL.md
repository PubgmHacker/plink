# Plink Backend Security Files — Установка

## Что внутри

```
src/
├── middleware/
│   └── security.ts          — host auth, senderID validation, bcrypt, rate limit
├── websocket/
│   └── ws-handler.ts        — безопасный WS handler (замена существующего)
└── routes/
    └── rooms.ts             — безопасные REST routes (замена существующего)
```

## Установка

1. npm install bcrypt

2. Скопировать файлы в backend-репозиторий:
   - src/middleware/security.ts
   - src/websocket/ws-handler.ts  (заменить существующий)
   - src/routes/rooms.ts          (заменить существующий)

3. В src/index.ts подключить:
   import { setupWebSocketHandler } from './websocket/ws-handler.js';
   import roomRoutes from './routes/rooms.js';
   setupWebSocketHandler(io, prisma, fastify);
   fastify.register(roomRoutes, { prefix: '/api' });

4. В Prisma schema убедиться что есть поля:
   model Room {
     password    String?   // bcrypt hash, nullable
     privacy     String    @default("public") // public | private | link
   }

5. Railway задеплоит автоматически.
