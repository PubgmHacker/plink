// vitest.config.ts
// Аудит 26.07.2026 (7.5): добавлен RedisSkipReporter — молчаливый скип
// интеграционных тестов без Redis теперь громко печатается в конце прогона.
import { defineConfig } from 'vitest/config';
import RedisSkipReporter from './src/tests/redisSkipReporter';

export default defineConfig({
  test: {
    // Только исходные тесты: vitest 4 иначе подхватывает и их скомпилированные
    // копии из dist/ — прогон удваивается, а устаревший dist роняет свежие
    // контракты.
    include: ['src/tests/**/*.test.ts'],
    reporters: ['default', new RedisSkipReporter()],
  },
});
