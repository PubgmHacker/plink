import { describe, expect, it, beforeEach, vi } from 'vitest';

vi.mock('../../config/redis.js', () => ({ redis: null }));

import {
  consumeResetCode,
  generateResetCode,
  hashResetCode,
  storeResetCode,
  __clearPasswordResetMemory,
} from '../../services/passwordReset.js';

describe('passwordReset', () => {
  beforeEach(() => {
    __clearPasswordResetMemory();
  });

  it('generates a 6-digit code', () => {
    const code = generateResetCode();
    expect(code).toMatch(/^\d{6}$/);
  });

  it('hashes the same email+code the same way', () => {
    const a = hashResetCode('A@Mail.com', '123456', 'pepper');
    const b = hashResetCode('a@mail.com', '123456', 'pepper');
    expect(a).toBe(b);
  });

  it('accepts a stored code once', async () => {
    await storeResetCode('user@plink.app', '654321');
    expect(await consumeResetCode('user@plink.app', '654321')).toBe('ok');
    expect(await consumeResetCode('user@plink.app', '654321')).toBe('expired');
  });

  it('rejects a wrong code and locks after five misses', async () => {
    await storeResetCode('user@plink.app', '111111');
    for (let i = 0; i < 4; i += 1) {
      expect(await consumeResetCode('user@plink.app', '000000')).toBe('invalid');
    }
    expect(await consumeResetCode('user@plink.app', '000000')).toBe('locked');
    expect(await consumeResetCode('user@plink.app', '111111')).toBe('expired');
  });
});
