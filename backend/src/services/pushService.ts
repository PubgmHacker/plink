// src/services/pushService.ts — APNs pushes (token-based provider auth, no SDK)
//
// Uses Node built-in http2 + jose (already a dependency) to talk to APNs
// directly. Configure with:
//   APNS_KEY_ID      — 10-char key id of the .p8 key
//   APNS_TEAM_ID     — Apple developer team id
//   APNS_PRIVATE_KEY — contents of the .p8 file (PEM; \n-escaped is OK)
//   APNS_BUNDLE_ID   — iOS bundle id (apns-topic)
//   APNS_PRODUCTION  — 'false' to use the sandbox gateway (default: true)
//
// The device token lives in User.fcmToken (historical column name; it holds
// the raw APNs token hex string sent by the iOS client via /auth/fcm-token).
// Every function is a best-effort no-op when APNs is not configured.

import http2 from 'node:http2';
import { SignJWT, importPKCS8 } from 'jose';
import { config } from '../config/index.js';
import { prisma } from '../config/db.js';

export interface PushContent {
  title: string;
  body: string;
  threadId?: string;
  badge?: number;
  data?: Record<string, unknown>;
}

export function isPushConfigured(): boolean {
  return Boolean(
    config.APNS_KEY_ID && config.APNS_TEAM_ID && config.APNS_PRIVATE_KEY && config.APNS_BUNDLE_ID,
  );
}

// APNs provider JWTs are valid 20–60 minutes; refresh at 40.
let cachedProviderJwt: { token: string; issuedAtMs: number } | null = null;

async function providerToken(): Promise<string> {
  const now = Date.now();
  if (cachedProviderJwt && now - cachedProviderJwt.issuedAtMs < 40 * 60 * 1000) {
    return cachedProviderJwt.token;
  }
  const pem = config.APNS_PRIVATE_KEY.replace(/\\n/g, '\n');
  const key = await importPKCS8(pem, 'ES256');
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: config.APNS_KEY_ID })
    .setIssuer(config.APNS_TEAM_ID)
    .setIssuedAt()
    .sign(key);
  cachedProviderJwt = { token, issuedAtMs: now };
  return token;
}

type SendResult = 'ok' | 'bad_token' | 'error';

function apnsHost(): string {
  return config.APNS_PRODUCTION
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';
}

async function sendToDevice(deviceToken: string, content: PushContent): Promise<SendResult> {
  const jwt = await providerToken();
  const payload = JSON.stringify({
    aps: {
      alert: { title: content.title, body: content.body },
      sound: 'default',
      ...(content.badge !== undefined ? { badge: content.badge } : {}),
      ...(content.threadId ? { 'thread-id': content.threadId } : {}),
    },
    ...(content.data ?? {}),
  });

  return new Promise<SendResult>((resolve) => {
    const client = http2.connect(apnsHost());
    const timer = setTimeout(() => {
      try {
        client.close();
      } catch {
        /* noop */
      }
      resolve('error');
    }, 10_000);
    client.on('error', () => {
      clearTimeout(timer);
      resolve('error');
    });
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': config.APNS_BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    });
    let status = 0;
    let bodyText = '';
    req.on('response', (headers) => {
      status = Number(headers[':status'] ?? 0);
    });
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      bodyText += chunk;
    });
    req.on('end', () => {
      clearTimeout(timer);
      client.close();
      if (status >= 200 && status < 300) return resolve('ok');
      if (status === 410) return resolve('bad_token');
      try {
        const reason = JSON.parse(bodyText)?.reason;
        if (
          reason === 'BadDeviceToken' ||
          reason === 'Unregistered' ||
          reason === 'DeviceTokenNotForTopic'
        ) {
          return resolve('bad_token');
        }
      } catch {
        /* fallthrough */
      }
      resolve('error');
    });
    req.on('error', () => {
      clearTimeout(timer);
      client.close();
      resolve('error');
    });
    req.end(payload);
  });
}

/** Send a push to one user (looks up the stored device token). Best-effort. */
export async function pushToUser(userId: string, content: PushContent): Promise<void> {
  if (!isPushConfigured()) return;
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true },
    });
    if (!user?.fcmToken) return;
    const result = await sendToDevice(user.fcmToken, content);
    if (result === 'bad_token') {
      await prisma.user.update({ where: { id: userId }, data: { fcmToken: null } }).catch(() => {});
    }
  } catch (err: any) {
    console.warn('[push] pushToUser failed:', err?.message ?? err);
  }
}

/** Broadcast to every user with a registered device token. Returns sent count. */
export async function pushBroadcast(content: PushContent): Promise<number> {
  if (!isPushConfigured()) return 0;
  let sent = 0;
  try {
    const users = await prisma.user.findMany({
      where: { fcmToken: { not: null }, deletedAt: null },
      select: { id: true, fcmToken: true },
    });
    const BATCH = 25;
    for (let i = 0; i < users.length; i += BATCH) {
      const batch = users.slice(i, i + BATCH);
      const results = await Promise.all(
        batch.map(async (u) => ({ u, r: await sendToDevice(u.fcmToken as string, content) })),
      );
      for (const { u, r } of results) {
        if (r === 'ok') sent++;
        if (r === 'bad_token') {
          await prisma.user
            .update({ where: { id: u.id }, data: { fcmToken: null } })
            .catch(() => {});
        }
      }
    }
  } catch (err: any) {
    console.warn('[push] pushBroadcast failed:', err?.message ?? err);
  }
  return sent;
}
