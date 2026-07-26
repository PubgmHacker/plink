# PLINK (Плинк)

Монорепо: SwiftUI iOS-клиент «Плинк» + Node/Fastify бэкенд.

```
PLINK/
├── ios-2/       # SwiftUI приложение (XcodeGen project.yml)
└── backend-3/   # Fastify + Prisma + PostgreSQL (деплой Railway)
```

## iOS — сборка через XcodeGen

В репо **не** лежит `.xcodeproj` — он генерируется из `ios-2/project.yml`.
После клона один раз:

```bash
cd ios-2
xcodegen generate        # создаст Plink.xcodeproj
open Plink.xcodeproj
```

Секреты (ключи) кладём в `ios-2/Secrets.xcconfig` (gitignored) —
см. шаблон `Secrets.xcconfig.template`. Без него AI/Yandex-фичи будут отключены.

### Запуск на реальном iPhone (iPhone 17 Pro Max)

1. Подключи телефон по USB, доверяй компьютеру.
2. В Xcode: **Window → Devices and Simulators** — телефон должен появиться.
3. Выбери схему **Plink** и таргет-устройство = твой iPhone.
4. Signing: Team `2QAMUC4Z4P`, стиль Automatic (уже зашито в `project.yml`).
5. ⌘R — соберётся и установится на устройство.

## Бэкенд — деплой на Railway

`backend-3/` уже настроен на Dockerfile-деплой (см. `railway.json`, `Dockerfile`).
Production URL зашит в iOS: `https://plink-backend-production-ef31.up.railway.app`.

Подробности по переменным окружения — см. `backend-3/.env.example` и раздел
«Variables» в этом репозитории.
