// src/tests/redisSkipReporter.ts
// Аудит 26.07.2026 (7.5): интеграционные тесты (src/tests/integration/*) молча
// скипались без Redis — «100 passed» на машине без Redis превращалось в 86,
// и никто этого не замечал. Этот репортер делает скип ГРОМКИМ: в конце прогона
// печатает предупреждение с количеством скипнутых интеграционных тестов.
//
// Подключается в vitest.config.ts рядом с default-репортером.
//
// 12.08.2026: переписан на reporter-API vitest 4 (onTestRunEnd + TestModule);
// прежний onFinished(files) в четвёртой мажорной версии больше не вызывается,
// то есть репортер тихо переставал предупреждать — ровно тот отказ, ради
// которого он существует.

import type { Reporter, TestModule } from 'vitest/node';

export default class RedisSkipReporter implements Reporter {
  onTestRunEnd(testModules: ReadonlyArray<TestModule> = []): void {
    let skipped = 0;
    for (const mod of testModules) {
      if (!mod.moduleId.includes('tests/integration')) continue;
      for (const test of mod.children.allTests()) {
        if (test.result().state === 'skipped') skipped++;
      }
    }
    if (skipped === 0) return;

    const reason = process.env.REDIS_URL
      ? `Redis недоступен по REDIS_URL=${process.env.REDIS_URL}`
      : 'нет REDIS_URL';
    // Нарочно в stderr и с рамкой — чтобы было видно в конце любого прогона.
    console.error('');
    console.error('──────────────────────────────────────────────────────────────');
    console.error(`⚠ ${skipped} интеграционных тестов скипнуто: ${reason}`);
    console.error('  Подними Redis и запусти: npm run test:integration');
    console.error('──────────────────────────────────────────────────────────────');
  }
}
