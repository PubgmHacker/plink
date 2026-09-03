// src/config/index.ts — Stabilize v2: typed config, aud allowlist, weak-secret guard
function required(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing env: ${key}`);
  return val;
}

function parseAudiences(raw: string | undefined): string[] {
  if (!raw) return ['plink-ios'];
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/** Tauri desktop + other native WebView origins (always allowed in prod). */
export const NATIVE_CLIENT_ORIGINS = [
  'tauri://localhost',
  'http://tauri.localhost',
  'https://tauri.localhost',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
] as const;

function parseCorsOrigin(raw: string | undefined): string | string[] {
  if (!raw || raw === '*') {
    // "*" with credentials is forbidden in production. We allow it only
    // for development to keep local iteration fast; production startup will
    // reject it (see assertProductionInvariants below).
    return '*';
  }
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

const jwtSecret = process.env.JWT_SECRET || 'dev-secret-change-me';

export const config = {
  DATABASE_URL: process.env.DATABASE_URL || required('DATABASE_URL'),
  JWT_SECRET: jwtSecret,
  JWT_ISSUER: process.env.JWT_ISSUER || 'plink',
  JWT_AUDIENCES: parseAudiences(process.env.JWT_AUDIENCES),
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'dev-refresh-secret-change-me',
  CORS_ORIGIN: parseCorsOrigin(process.env.CORS_ORIGIN),

  PORT: parseInt(process.env.PORT || '8080'),

  REDIS_URL: process.env.REDIS_URL || '',
  SENTRY_DSN: process.env.SENTRY_DSN || '',
  SLACK_WEBHOOK_URL: process.env.SLACK_WEBHOOK_URL || '',

  // Token TTLs
  // P0 hardening: short-lived access tokens (refresh rotation handles renewal)
  ACCESS_TOKEN_TTL: process.env.ACCESS_TOKEN_TTL || '1h',
  REFRESH_TOKEN_TTL_DAYS: parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '90'),

  // Realtime ticket endpoint: short-lived, single-use nonce
  REALTIME_TICKET_TTL_SEC: parseInt(process.env.REALTIME_TICKET_TTL_SEC || '60'),

  // Signed media URL TTL: 60–300 seconds
  SIGNED_MEDIA_URL_TTL: parseInt(process.env.SIGNED_MEDIA_URL_TTL || '120'),

  // Feature flags — see rollout plan
  APP_STORE_COMPLIANT: process.env.APP_STORE_COMPLIANT !== 'false',
  ENABLE_LEGACY_STREAM_RELAY: process.env.ENABLE_LEGACY_STREAM_RELAY === 'true',
  REALTIME_PROTOCOL_V2: process.env.REALTIME_PROTOCOL_V2 !== 'false',
  NATIVE_PLAYER_V2: process.env.NATIVE_PLAYER_V2 !== 'false',
  LIVEKIT_SFU: process.env.LIVEKIT_SFU === 'true',
  WATCH_SCREEN_V2: process.env.WATCH_SCREEN_V2 === 'true',

  // LiveKit (Stage 9)
  LIVEKIT_URL: process.env.LIVEKIT_URL || '',
  LIVEKIT_API_KEY: process.env.LIVEKIT_API_KEY || '',
  LIVEKIT_API_SECRET: process.env.LIVEKIT_API_SECRET || '',

  // APNs push notifications (token-based provider auth, .p8 key)
  APNS_KEY_ID: process.env.APNS_KEY_ID || '',
  APNS_TEAM_ID: process.env.APNS_TEAM_ID || '',
  APNS_PRIVATE_KEY: process.env.APNS_PRIVATE_KEY || '',
  APNS_BUNDLE_ID: process.env.APNS_BUNDLE_ID || '',
  APNS_PRODUCTION: process.env.APNS_PRODUCTION !== 'false',

  /// Bundle ID / Services ID for Sign in with Apple (JWT `aud`).
  APPLE_CLIENT_ID:
    process.env.APPLE_CLIENT_ID || process.env.APNS_BUNDLE_ID || 'com.syncwatch.plink',

  NODE_ENV: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',

  PUBLIC_BASE_URL: process.env.PUBLIC_BASE_URL || 'https://plink-production.up.railway.app',

  // Dev-only emergency DB wipe (POST /api/dev/wipe-db)
  DEV_WIPE_SECRET: process.env.DEV_WIPE_SECRET || '',
  ENABLE_DEV_WIPE: process.env.ENABLE_DEV_WIPE === 'true',
};

/**
 * Production startup must refuse to boot on weak/default secrets and on
 * CORS "*" with credentials. Called from app.ts during bootstrap.
 */
/**
 * CORS origin resolver for @fastify/cors.
 * In dev reflects any origin; in prod allows CORS_ORIGIN + native desktop clients.
 */
export function resolveCorsOrigin():
  | boolean
  | ((origin: string | undefined, cb: (err: Error | null, allow: boolean) => void) => void) {
  if (!config.isProduction) return true;

  const configured =
    config.CORS_ORIGIN === '*'
      ? []
      : Array.isArray(config.CORS_ORIGIN)
        ? config.CORS_ORIGIN
        : [config.CORS_ORIGIN];

  const allowed = [...configured, ...NATIVE_CLIENT_ORIGINS];

  return (origin, cb) => {
    if (!origin) {
      cb(null, true);
      return;
    }
    if (allowed.includes(origin)) {
      cb(null, true);
      return;
    }
    cb(new Error(`CORS origin not allowed: ${origin}`), false);
  };
}

export function assertProductionInvariants(): void {
  if (!config.isProduction) return;

  const weakSecrets = new Set([
    'dev-secret-change-me',
    'dev-refresh-secret-change-me',
    'your-super-secret-key-change-me',
    'replace-with-strong-32-char-min-secret',
    'changeme',
    'secret',
  ]);
  if (weakSecrets.has(config.JWT_SECRET) || config.JWT_SECRET.length < 32) {
    throw new Error(
      `FATAL: JWT_SECRET is weak or default in production (len=${config.JWT_SECRET.length}). ` +
        `Rotate immediately and set JWT_SECRET to a >=32-char random string.`,
    );
  }
  if (
    weakSecrets.has(config.JWT_REFRESH_SECRET) ||
    config.JWT_REFRESH_SECRET.length < 32 ||
    config.JWT_REFRESH_SECRET === config.JWT_SECRET
  ) {
    throw new Error(
      'FATAL: JWT_REFRESH_SECRET must be a distinct >=32-char random secret in production.',
    );
  }
  if (config.CORS_ORIGIN === '*') {
    throw new Error(
      'FATAL: CORS_ORIGIN="*" with credentials is forbidden in production. ' +
        'Set an explicit allowlist (comma-separated origins).',
    );
  }
  if (config.JWT_AUDIENCES.length === 0) {
    throw new Error('FATAL: JWT_AUDIENCES must contain at least one audience in production.');
  }
}

// Production invariants are executed from app bootstrap after config is loaded.
// Keep the checks centralized in assertProductionInvariants().
