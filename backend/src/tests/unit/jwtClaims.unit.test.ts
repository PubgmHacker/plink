// Pins the JWT audience/issuer allowlist.
//
// @fastify/jwt is backed by fast-jwt, which reads `allowedAud`/`allowedIss`.
// Passing verify options as `{ audience, issuer }` is silently accepted and
// checks nothing. Signing compounded it: without an `aud` claim, fast-jwt skips
// the validator entirely rather than rejecting the token.
//
// This test asserts both directions — the correct option names do reject a
// foreign aud/iss, and the old names do not.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import Fastify from 'fastify';
import jwt from '@fastify/jwt';

const SECRET = 'x'.repeat(40);
const AUDS = ['plink-ios', 'plink-android'];

async function makeApp(opts: any) {
  const app = Fastify();
  await app.register(jwt, { secret: SECRET, ...opts } as any);
  return app;
}

function claims() {
  const now = Math.floor(Date.now() / 1000);
  return { id: 'u1', iat: now, exp: now + 3600 };
}

describe('JWT aud/iss allowlist', () => {
  it('подписывает токен с aud из JWT_AUDIENCES', async () => {
    const app = await makeApp({
      sign: { algorithm: 'HS256', iss: 'plink', aud: AUDS[0] },
      verify: { allowedAud: AUDS, allowedIss: 'plink' },
    });
    const token = app.jwt.sign(claims());
    const decoded = app.jwt.decode(token) as any;
    expect(decoded.aud).toBe('plink-ios');
    expect(decoded.iss).toBe('plink');
    expect(() => app.jwt.verify(token)).not.toThrow();
  });

  it('отвергает токен с чужим aud и с чужим iss', async () => {
    const app = await makeApp({
      sign: { algorithm: 'HS256', iss: 'plink', aud: AUDS[0] },
      verify: { allowedAud: AUDS, allowedIss: 'plink' },
    });
    const foreignAud = await makeApp({
      sign: { algorithm: 'HS256', iss: 'plink', aud: 'evil-service' },
    });
    const foreignIss = await makeApp({ sign: { algorithm: 'HS256', iss: 'other', aud: AUDS[0] } });

    expect(() => app.jwt.verify(foreignAud.jwt.sign(claims()))).toThrow();
    expect(() => app.jwt.verify(foreignIss.jwt.sign(claims()))).toThrow();
  });

  it('старые токены без aud продолжают проходить verify (без разлогина при деплое)', async () => {
    const app = await makeApp({
      sign: { algorithm: 'HS256', iss: 'plink', aud: AUDS[0] },
      verify: { allowedAud: AUDS, allowedIss: 'plink' },
    });
    const legacy = await makeApp({ sign: { algorithm: 'HS256', iss: 'plink' } });
    expect(() => app.jwt.verify(legacy.jwt.sign(claims()))).not.toThrow();
  });

  it('старые имена опций (audience/issuer) ничего не проверяют', async () => {
    const app = await makeApp({
      sign: { algorithm: 'HS256', iss: 'plink' },
      verify: { audience: AUDS, issuer: 'plink' },
    });
    const foreign = await makeApp({
      sign: { algorithm: 'HS256', iss: 'other', aud: 'evil-service' },
    });
    // Именно поэтому дефект и не был виден: чужой токен проходил насквозь.
    expect(() => app.jwt.verify(foreign.jwt.sign(claims()))).not.toThrow();
  });

  it('app.ts использует рабочие имена опций', () => {
    const src = readFileSync(new URL('../../app.ts', import.meta.url), 'utf8');
    expect(src).toContain('allowedAud');
    expect(src).toContain('allowedIss');
    expect(src).toMatch(/aud: jwtAudiences\[0\]/);
  });
});
