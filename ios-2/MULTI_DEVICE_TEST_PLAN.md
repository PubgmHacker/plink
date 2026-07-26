# MULTI_DEVICE_TEST_PLAN — Plink Sync Test

**Backend URL:** `https://plink-backend-production-ef31.up.railway.app`  
**Wipe secret:** `plink-test-2026` (dev only — remove before App Store)

---

## Цель теста

Доказать, что 2+ устройства в одной Plink-комнате имеют:

- Синхронизированный чат (сообщения видны на всех)
- Синхронизированный presence (аватары обновляются)
- Синхронизированный player (timestamp ±2 секунды)
- Стабильность 30+ минут

---

## Устройства для теста

| Устройство 1 | Устройство 2 (минимум) | Устройство 3 (опционально) |
|--------------|------------------------|----------------------------|
| iPhone с `.ipa` | Windows web client | Android `.apk` (когда будет) |

---

## Подготовка

### 1. Backend (5 минут)

- [ ] Railway deployed (uptime <60s = fresh deploy)
- [ ] `GET /health` → 200
- [ ] `POST /api/dev/wipe-db` → 200 с секретом `plink-test-2026`
- [ ] Env vars: `ENABLE_DEV_WIPE=true`, `DEV_WIPE_SECRET=plink-test-2026`

Проверка:

```bash
curl https://plink-backend-production-ef31.up.railway.app/health

curl -X POST https://plink-backend-production-ef31.up.railway.app/api/dev/wipe-db \
  -H "Content-Type: application/json" \
  -d '{"secret":"plink-test-2026"}'
```

### 2. iOS устройство (10 минут)

- [ ] UDID добавлен в Apple Developer Portal → Devices
- [ ] Provisioning profile включает UDID
- [ ] Установить `plink-ios/build/ipa/Plink.ipa` через AltStore / Sideloadly / Apple Configurator 2
- [ ] Settings → General → VPN & Device Management → trust developer cert
- [ ] App запускается, показывает экран логина

### 3. Windows web клиент (2 минуты)

```bash
cd Desktop/Grok/windows-client
npm install
npm run dev
# → http://localhost:5173
```

- [ ] В `src/lib/api.ts` стоит Railway URL (не localhost)
- [ ] Открыть в Chrome/Edge
- [ ] Регистрация и логин работают

---

## TEST 1: Cross-Device Auth (5 минут)

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 1.1 | iPhone | Регистрация: `ios@test.com` / `test123` / username `iosusr` | Успех, Home |
| 1.2 | Windows web | Регистрация: `web@test.com` / `test123` / username `webusr` | Успех, Home |
| 1.3 | iPhone | Logout | Экран логина |
| 1.4 | iPhone | Login `ios@test.com` | Успех, данные восстановлены |
| 1.5 | Windows web | Logout + Login | Успех |

**Проход:** ✅ / ❌  
**Заметки:** ___________

---

## TEST 2: Avatar Cross-Platform (5 минут)

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 2.1 | iPhone | Profile → фото → upload | Аватар виден на Home и Profile |
| 2.2 | Windows web | В комнате с iOS User | iOS User с аватаром в presence |
| 2.3 | Windows web | Profile → сменить аватар | Аватар сохранён |
| 2.4 | iPhone | Комната с Web User | Web User с новым аватаром |

**Проход:** ✅ / ❌  
**Заметки:** ___________

---

## TEST 3: Room Creation + Presence (10 мин) ⭐ КРИТИЧНЫЙ

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 3.1 | iPhone | Home → New Room → YouTube → Create | Редирект в комнату |
| 3.2 | iPhone | Presence bar | 1 человек / твой аватар |
| 3.3 | iPhone | Скопировать room code | Код в буфере |
| 3.4 | Windows web | Join by code | Та же комната |
| 3.5 | iPhone | Presence bar | 2 человека |
| 3.6 | Windows web | Presence bar | 2 аватара |
| 3.7 | iPhone | Выйти из комнаты | На Windows: 1 человек |

**Проход:** ✅ / ❌  
**Заметки:** ___________

---

## TEST 4: Chat Sync (10 мин) ⭐⭐ КРИТИЧНЫЙ

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 4.1 | iPhone | "Привет с iPhone!" | Видно на iPhone |
| 4.2 | Windows web | — | Сообщение <1s |
| 4.3 | Windows web | "Привет с Windows!" | Видно на Windows |
| 4.4 | iPhone | — | Сообщение <1s |
| 4.5 | iPhone | 5 сообщений быстро | Все на Windows, порядок верный |
| 4.6 | Windows web | Эмодзи реакция | Видна на iPhone (если поддерживается) |
| 4.7 | iPhone | Scroll вверх | История подгружается |

**Проход:** ✅ / ❌  
**Latency:** ______ ms

---

## TEST 5: Player Sync (10 мин) ⭐⭐⭐ КРИТИЧНЕЙШИЙ

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 5.1 | iPhone (host) | Play | Видео играет |
| 5.2 | Windows web | — | Старт за 3s |
| 5.3 | iPhone | Timestamp | Например 1:23 |
| 5.4 | Windows web | Timestamp | 1:21–1:25 (±2s) |
| 5.5 | iPhone | Pause | Стоп |
| 5.6 | Windows web | — | Пауза за 2s |
| 5.7 | iPhone | Seek 5:00 | Перемотка |
| 5.8 | Windows web | — | 5:00 ±2s |
| 5.9 | iPhone | Play | Синхронно |

**Проход:** ✅ / ❌  
**Sync drift:** ±______ секунд

---

## TEST 6: Reactions (5 минут)

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 6.1 | iPhone | ❤️ | Danmaku на iPhone |
| 6.2 | Windows web | — | Реакция видна |
| 6.3 | Windows web | 🔥 | На iPhone |
| 6.4 | iPhone | 10 реакций | Без лагов |

**Проход:** ✅ / ❌

---

## TEST 7: Disconnect / Reconnect (10 минут)

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 7.1 | iPhone | Airplane Mode ON | WS disconnect |
| 7.2 | Windows web | — | iOS offline через 10–30s |
| 7.3 | iPhone | Airplane Mode OFF | Auto-reconnect |
| 7.4 | iPhone | — | Presence + chat catch-up |
| 7.5 | Windows web | Сообщение пока iPhone offline | Доставлено после reconnect |
| 7.6 | iPhone | Прочитать | OK |

**Проход:** ✅ / ❌

---

## TEST 8: 30-Minute Stability (30 минут)

| Шаг | Устройство | Действие | Ожидаемый результат |
|-----|------------|----------|---------------------|
| 8.1 | Оба | 30 мин в комнате | Без крашей |
| 8.2 | iPhone | Memory (Xcode) | <200 MB |
| 8.3 | iPhone | CPU idle | <15% |
| 8.4 | Оба | 50 сообщений каждый | Без дубликатов |
| 8.5 | iPhone | Enter/exit 5 раз | Без утечек |

**Проход:** ✅ / ❌

---

## Отчёт по тесту

```
Тест проводил: ___________
Дата: 2026-___-___
iOS устройство: ___________ (модель + iOS version)
Windows: browser + OS version

TEST 1 (Auth):            ✅ / ❌
TEST 2 (Avatar):          ✅ / ❌
TEST 3 (Presence):        ✅ / ❌
TEST 4 (Chat Sync):        ✅ / ❌ — latency: ___ ms
TEST 5 (Player Sync):      ✅ / ❌ — drift: ±___ s
TEST 6 (Reactions):         ✅ / ❌
TEST 7 (Reconnect):         ✅ / ❌
TEST 8 (30min stability):   ✅ / ❌

КРИТИЧЕСКИЕ БАГИ:
1. ___________
2. ___________

НЕ-БЛОКИРУЮЩИЕ БАГИ:
1. ___________

Общий вердикт: READY FOR BETA / NEEDS FIXES
```

---

## Критерии успеха

Тест пройден если:

- TEST 3 (Presence) = ✅
- TEST 4 (Chat Sync) = ✅, latency <2s
- TEST 5 (Player Sync) = ✅, drift ±2s
- TEST 8 (Stability) = ✅, 30 мин без крашей

---

## Troubleshooting

| Симптом | Что проверить |
|---------|---------------|
| Не логинится iOS | Railway URL в `APIClient.swift` |
| Сообщения не доходят | WS в Chrome DevTools → Network → WS |
| Presence = 0 | Heartbeat / WS reconnect |
| Player не синхронный | Host controls + sync protocol |
| Аватар не грузится | `GET /users/me` → `avatarData` / `avatarURL` |
| Краш при создании комнаты | `mediaItem` не null |

---

## Reset между тестами

```bash
curl -X POST https://plink-backend-production-ef31.up.railway.app/api/dev/wipe-db \
  -H "Content-Type: application/json" \
  -d '{"secret":"plink-test-2026"}'
```