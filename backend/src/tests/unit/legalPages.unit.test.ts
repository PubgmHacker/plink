// legalPages.unit.test.ts — the public legal, support and purchase pages.
//
// Why these are worth a test: the iOS paywall and Settings link to /terms and
// /privacy, and App Review 3.1.2 rejects a subscription app whose links are
// dead. Nothing in the type system notices when a route is deleted or a footer
// link is dropped during a redesign, so the invariants are pinned here:
//
//   1. /terms, /privacy and /support answer 200 with HTML.
//   2. Every section of the canonical documents reaches the page.
//   3. The purchase page (/plus) and the home page link to both documents.
//   4. The pages carry no external <script src> — the strict CSP has no
//      'unsafe-inline' for scripts, and the CI security job forbids external
//      sources in server-rendered pages.
//
// prisma is mocked because importing web.ts pulls it in; the routes exercised
// here never touch the database.

import { describe, expect, it, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

vi.mock('../../config/db.js', () => ({
  prisma: {
    user: { findFirst: vi.fn() },
    room: { findFirst: vi.fn() },
  },
}));

vi.mock('../../utils/audit.js', () => ({ logAudit: vi.fn(), AuditActions: {} }));

import { webRoutes } from '../../routes/web.js';
import { PRIVACY, SUPPORT_EMAIL, TERMS } from '../../web/legal.js';

async function appWithWebRoutes(): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(webRoutes);
  await app.ready();
  return app;
}

async function get(path: string) {
  const app = await appWithWebRoutes();
  try {
    return await app.inject({ method: 'GET', url: path });
  } finally {
    await app.close();
  }
}

describe('legal pages', () => {
  it('serves /terms with every section of the canonical document', async () => {
    const res = await get('/terms');
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain(TERMS.heading);
    expect(res.body).toContain(TERMS.updated);
    for (const section of TERMS.sections) {
      expect(res.body).toContain(section.heading);
    }
  });

  it('serves /privacy with every section of the canonical document', async () => {
    const res = await get('/privacy');
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain(PRIVACY.heading);
    for (const section of PRIVACY.sections) {
      expect(res.body).toContain(section.heading);
    }
  });

  it('serves /support with a contact address', async () => {
    const res = await get('/support');
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain(`mailto:${SUPPORT_EMAIL}`);
  });

  it('states both payment paths in the subscription clause', async () => {
    // Apple requires the auto-renewing terms; the site sells a one-off through
    // YooKassa. A document that names only one of the two contradicts the product.
    const clause = TERMS.sections.find((s) => s.heading.includes('Plink+'));
    expect(clause).toBeDefined();
    expect(clause?.body).toContain('App Store');
    expect(clause?.body).toContain('24 часа');
    expect(clause?.body).toContain('ЮKassa');
  });

  it('links both documents from the purchase page', async () => {
    const res = await get('/plus');
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('href="/terms"');
    expect(res.body).toContain('href="/privacy"');
  });

  it('links both documents from the home page', async () => {
    const res = await get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('href="/terms"');
    expect(res.body).toContain('href="/privacy"');
  });

  it('pulls in no external scripts and keeps the strict CSP', async () => {
    for (const path of ['/terms', '/privacy', '/support']) {
      const res = await get(path);
      expect(res.body).not.toMatch(/<script[^>]+src=/);
      const csp = String(res.headers['content-security-policy'] ?? '');
      expect(csp).toContain("default-src 'none'");
      expect(csp).toMatch(/script-src 'nonce-/);
    }
  });

  it('escapes the document text rather than trusting it', async () => {
    // The documents are ours, not user input — but a copy edit must never be
    // able to inject markup, so the renderer escapes and the bodies stay plain.
    for (const doc of [TERMS, PRIVACY]) {
      for (const section of doc.sections) {
        expect(section.body).not.toMatch(/[<>]/);
        expect(section.heading).not.toMatch(/[<>]/);
        expect(section.body.trim().length).toBeGreaterThan(0);
      }
    }
  });
});
