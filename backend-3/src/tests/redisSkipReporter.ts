// src/tests/redisSkipReporter.ts
// Аудит 26.07.2026 (7.5): интеграционные тесты (src/tests/integration/*) молча
// скипались без Redis — «100 passed» на машине без Redis превращалось в 86,
// и никто этого не замечал. Этот репортер делает скип ГРОМКИМ: в конце прогона
// печатает предупреждение с количеством скипнутых интеграционных тестов.
//
// Подключается в vitest.config.ts рядом с default-репортером.

interface MinimalTask {
  type: string;
  mode: string;
  filepath?: string;
  tasks?: MinimalTask[];
  file?: { filepath?: string };
}

function countSkippedTests(task: MinimalTask, ancestorSkipped = false): number {
  // Внутри describe.skipIf(...) дочерние тесты считаются скипнутыми,
  // даже если их собственный mode остался 'run'.
  const skippedHere = ancestorSkipped || task.mode === 'skip' || task.mode === 'todo';
  if (task.type === 'test') {
    return skippedHere ? 1 : 0;
  }
  let n = 0;
  for (const child of task.tasks ?? []) {
    n += countSkippedTests(child, skippedHere);
  }
  return n;
}

export default class RedisSkipReporter {
  onFinished(files: MinimalTask[] = []): void {
    let skipped = 0;
    for (const file of files) {
      const filepath = file.filepath ?? file.file?.filepath ?? '';
      if (!filepath.includes('tests/integration')) continue;
      skipped += countSkippedTests(file);
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
