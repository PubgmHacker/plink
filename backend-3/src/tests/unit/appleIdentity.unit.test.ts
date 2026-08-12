import { describe, expect, it } from 'vitest';
import { usernameFromAppleSub } from '../../utils/appleIdentity.js';

describe('usernameFromAppleSub', () => {
  it('produces a signup-valid username from an Apple sub', () => {
    const u = usernameFromAppleSub('001234.abcdef0123456789.1234');
    expect(u).toMatch(/^[A-Za-z][A-Za-z0-9_]{4,31}$/);
    expect(u.startsWith('apl_')).toBe(true);
  });

  it('stays within 32 chars', () => {
    const u = usernameFromAppleSub('x'.repeat(80));
    expect(u.length).toBeLessThanOrEqual(32);
  });
});
