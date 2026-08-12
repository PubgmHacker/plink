// Verify Sign in with Apple identity tokens via Apple JWKS (jose).
import * as jose from 'jose';
import { config } from '../config/index.js';

const appleJWKS = jose.createRemoteJWKSet(
  new URL('https://appleid.apple.com/auth/keys'),
);

export type AppleIdentity = {
  sub: string;
  email: string | null;
  emailVerified: boolean;
};

export async function verifyAppleIdentityToken(identityToken: string): Promise<AppleIdentity> {
  const { payload } = await jose.jwtVerify(identityToken, appleJWKS, {
    issuer: 'https://appleid.apple.com',
    audience: config.APPLE_CLIENT_ID,
  });

  const sub = typeof payload.sub === 'string' ? payload.sub : '';
  if (!sub) {
    throw new Error('Apple identity token missing sub');
  }

  const email = typeof payload.email === 'string' ? payload.email : null;
  const emailVerified =
    payload.email_verified === true ||
    payload.email_verified === 'true';

  return { sub, email, emailVerified };
}

/** Stable username from Apple sub — always matches signup regex. */
export function usernameFromAppleSub(sub: string): string {
  const hex = sub.replace(/[^a-zA-Z0-9]/g, '').slice(0, 16) || 'user';
  const base = `apl_${hex}`.slice(0, 32);
  if (/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(base)) return base.toLowerCase();
  return `apl_${hex.padEnd(4, '0')}`.slice(0, 32).toLowerCase();
}
