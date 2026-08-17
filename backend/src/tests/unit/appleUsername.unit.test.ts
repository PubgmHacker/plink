// Unit test for the pure half of Apple sign-in.
//
// Imports ../../utils/appleUsername.js rather than appleIdentity.js: the latter
// reads the validated config at import time, so this file used to fail to load
// with "Missing env: DATABASE_URL" on a machine without one — a unit test that
// needed a database URL to test a string function.
import { describe, expect, it } from 'vitest';
import { usernameFromAppleSub } from '../../utils/appleUsername.js';

const SIGNUP_USERNAME = /^[A-Za-z][A-Za-z0-9_]{4,31}$/;

describe('usernameFromAppleSub', () => {
  it('produces a signup-valid username from a real Apple sub', () => {
    const u = usernameFromAppleSub('001234.abcdef0123456789.1234');
    expect(u).toMatch(SIGNUP_USERNAME);
    expect(u.startsWith('apl_')).toBe(true);
  });

  it('stays within the 32-char column limit', () => {
    const u = usernameFromAppleSub('x'.repeat(80));
    expect(u.length).toBeLessThanOrEqual(32);
    expect(u).toMatch(SIGNUP_USERNAME);
  });

  it('is stable — the same sub always yields the same username', () => {
    const sub = '001234.abcdef0123456789.1234';
    expect(usernameFromAppleSub(sub)).toBe(usernameFromAppleSub(sub));
  });

  it('is lowercase, because usernames are compared case-insensitively', () => {
    expect(usernameFromAppleSub('001234.ABCDEF.99')).toBe(
      usernameFromAppleSub('001234.ABCDEF.99').toLowerCase(),
    );
  });

  // The degenerate inputs. A sub of punctuation only, or a single character, still
  // has to clear the signup regex — that is the whole contract of this function,
  // and these are the cases where it is least obvious that it does.
  it.each([
    ['a sub of punctuation only', '....'],
    ['an empty sub', ''],
    ['a single-character sub', 'a'],
    ['a single-digit sub', '7'],
  ])('produces a signup-valid username from %s', (_label, sub) => {
    expect(usernameFromAppleSub(sub)).toMatch(SIGNUP_USERNAME);
  });
});
