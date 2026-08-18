// autoMod.unit.test.ts — юнит-тесты автомодерации (без БД: prisma замокан).
// Карта strikes росла бесконечно — проверяем ленивую чистку.

import { describe, it, expect, vi, afterEach } from 'vitest';

vi.mock('../../config/db.js', () => ({ prisma: {} }));

import { muteUser, muteRemainingSec, __automodMapSizes } from '../../moderation/autoMod.js';

afterEach(() => {
  vi.useRealTimers();
});

describe('autoMod mutes', () => {
  it('эскалирует мут в окне страйков', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-26T00:00:00Z'));
    expect(muteUser('room-esc', 'u-esc', 'profanity')).toBe(60);
    expect(muteUser('room-esc', 'u-esc', 'profanity')).toBe(180);
    expect(muteUser('room-esc', 'u-esc', 'profanity')).toBe(600);
  });

  it('чистит истёкшие муты и страйки, а не копит ключи до рестарта', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-07-26T01:00:00Z'));
    muteUser('room-prune-1', 'u-prune-1', 'profanity');
    muteUser('room-prune-2', 'u-prune-2', 'profanity');
    const before = __automodMapSizes();
    expect(before.mutes).toBeGreaterThanOrEqual(2);
    expect(before.strikes).toBeGreaterThanOrEqual(2);

    // Окно страйков (10 мин) и мут истекли.
    vi.setSystemTime(new Date('2026-07-26T01:15:00Z'));
    expect(muteRemainingSec('room-prune-1', 'u-prune-1')).toBe(0);

    const after = __automodMapSizes();
    expect(after.mutes).toBeLessThan(before.mutes);
    expect(after.strikes).toBeLessThan(before.strikes);
    // Ключи второго пользователя тоже вычищены, хотя его никто не опрашивал.
    expect(muteRemainingSec('room-prune-2', 'u-prune-2')).toBe(0);
  });
});
