// Derives a Plink username from an Apple `sub` claim.
//
// Separate from appleIdentity.ts on purpose. That module constructs a remote JWKS
// client and reads the validated config at import time, so anything importing it
// needs DATABASE_URL set before the process starts (ADR-0006). This function is
// pure string work with no configuration and no network, and keeping it here is
// what lets its unit test be an actual unit test rather than a test that boots
// the config layer.
//
// The regex is the signup validator from routes/auth.ts: a leading letter, then
// 4–31 of [A-Za-z0-9_]. A username that fails it is rejected at signup, so this
// function must never return one.
//
// The second return is unreachable as written, and deliberately kept. `hex` is
// between 1 and 16 characters — non-alphanumerics are stripped, the result is
// truncated to 16, and `|| 'user'` covers the empty case — so `apl_${hex}` is
// always 5 to 20 characters of letters, digits and one underscore, which the regex
// always accepts. It is the guard that makes the invariant hold if someone later
// widens the slice or drops the `|| 'user'` fallback, and it costs one branch.

/** Stable username from an Apple `sub`. Always matches the signup regex. */
export function usernameFromAppleSub(sub: string): string {
  const hex = sub.replace(/[^a-zA-Z0-9]/g, '').slice(0, 16) || 'user';
  const base = `apl_${hex}`.slice(0, 32);
  if (/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(base)) return base.toLowerCase();
  return `apl_${hex.padEnd(4, '0')}`.slice(0, 32).toLowerCase();
}
