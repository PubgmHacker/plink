// Verify Sign in with Apple identity tokens via Apple JWKS (jose).
//
// Importing this module reads the validated config, which fails fast when
// DATABASE_URL is unset (ADR-0006). usernameFromAppleSub needs neither config nor
// network, so it lives in ./appleUsername.js and is re-exported here to keep the
// single import in routes/auth.ts intact.
import * as jose from 'jose';
import { config } from '../config/index.js';

export { usernameFromAppleSub } from './appleUsername.js';

const appleJWKS = jose.createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

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
  const emailVerified = payload.email_verified === true || payload.email_verified === 'true';

  return { sub, email, emailVerified };
}
