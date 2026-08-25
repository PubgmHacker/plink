import { PrismaClient } from '@prisma/client';

// Pool sizing must be explicit. Without connection_limit, Prisma's Rust query
// engine sizes the pool from the HOST's core count (num_cpus*2+1) — on a large
// Railway host that is 50+ connections per replica, so total Postgres
// connections become (unknown number) × (replica count) with no ceiling anyone
// chose. Set DB_POOL_SIZE per replica so total = DB_POOL_SIZE × replicas stays
// under the Postgres max_connections with headroom for migrations and psql.
// pool_timeout raised from Prisma's 10s default so a burst queues briefly
// instead of failing with P2024 at exactly the moment load spikes.
const POOL_SIZE = Math.max(1, parseInt(process.env.DB_POOL_SIZE || '15', 10) || 15);
const POOL_TIMEOUT_S = Math.max(1, parseInt(process.env.DB_POOL_TIMEOUT_S || '20', 10) || 20);

function withPoolParams(url: string): string {
  try {
    const u = new URL(url);
    // Respect an operator who already tuned the URL by hand.
    if (!u.searchParams.has('connection_limit')) {
      u.searchParams.set('connection_limit', String(POOL_SIZE));
    }
    if (!u.searchParams.has('pool_timeout')) {
      u.searchParams.set('pool_timeout', String(POOL_TIMEOUT_S));
    }
    if (!u.searchParams.has('connect_timeout')) {
      u.searchParams.set('connect_timeout', '10');
    }
    return u.toString();
  } catch {
    // Malformed URL — let PrismaClient produce its own (clearer) error.
    return url;
  }
}

const baseUrl = process.env.DATABASE_URL;

export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'production' ? ['error'] : ['query', 'error', 'warn'],
  // Unset DATABASE_URL (unit tests) keeps the old lazy behavior: construction
  // succeeds and only an actual query fails.
  ...(baseUrl ? { datasourceUrl: withPoolParams(baseUrl) } : {}),
});
