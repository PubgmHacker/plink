#!/usr/bin/env node
// Аудит 26.07.2026 (7.5): страж для npm run test:integration.
// Интеграционные тесты скипаются без Redis — этот скрипт не даёт запустить
// «интеграционный» прогон, который на деле ничего не проверит.
if (!process.env.REDIS_URL) {
  console.error('Ошибка: REDIS_URL не задан — интеграционные тесты требуют живой Redis.');
  console.error('Пример: REDIS_URL="redis://localhost:6380" npm run test:integration');
  process.exit(1);
}
