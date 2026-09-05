import { describe, expect, it } from 'vitest';
import Fastify from 'fastify';
import jwt from '@fastify/jwt';

describe('media stream token profile', () => {
  it('requires the explicit media_stream type', async () => {
    const app = Fastify();
    await app.register(jwt, { secret: 'x'.repeat(40) });
    const token = app.jwt.sign({ id: 'u1', scope: 'media', typ: 'media_stream' });
    const payload = app.jwt.verify(token) as { scope?: string; typ?: string };
    expect(payload.scope).toBe('media');
    expect(payload.typ).toBe('media_stream');
  });
});
