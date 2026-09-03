// src/tests/integration/happyPath.e2e.test.ts
// Full end-to-end happy path against a RUNNING backend:
//   signup host + viewer → create room → join → realtime tickets →
//   WebSocket connect → host play command → viewer receives sync.state →
//   chat message delivered to the viewer.
//
// Every release runs this against the freshly deployed backend — release.md §5.
// It is opt-in via E2E=1 because it needs live infrastructure (Postgres + Redis +
// backend) and leaves two throwaway `e2e_*@plink.lab` accounts behind. Locally:
//
//   docker compose -f tests/integration/docker-compose.yml up -d
//   DATABASE_URL="postgresql://plink:plink@localhost:5433/plink" \
//   REDIS_URL="redis://localhost:6380" npm run dev &
//   E2E=1 API_BASE=http://localhost:8080 npx vitest run src/tests/integration/happyPath.e2e.test.ts

import { describe, it, expect } from 'vitest';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';

const API_BASE = (process.env.API_BASE || 'http://localhost:8080').replace(/\/$/, '');
const WS_BASE = API_BASE.replace(/^http/, 'ws');

async function json(path: string, opts: { method?: string; token?: string; body?: unknown } = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    method: opts.method || 'GET',
    headers: {
      'Content-Type': 'application/json',
      ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok)
    throw new Error(`${opts.method || 'GET'} ${path} → ${res.status} ${JSON.stringify(data)}`);
  return data as any;
}

async function signup(label: string) {
  const suffix = `${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  return json('/api/auth/signup', {
    method: 'POST',
    body: {
      email: `e2e_${label}_${suffix}@plink.lab`,
      password: 'HappyPath123!',
      username: `e${label}${suffix}`.replace(/[^a-zA-Z0-9]/g, '').slice(0, 20),
    },
  });
}

type AnyMsg = Record<string, any>;

async function openClient(token: string, roomId: string, name: string) {
  const t = await json('/api/realtime/ticket', { method: 'POST', token, body: { roomId } });
  const protocols: string[] = t.protocol?.length
    ? t.protocol
    : ['plink.v2', `plink.ticket.${t.ticket}`];
  const ws = new WebSocket(`${WS_BASE}/ws/room/${roomId}`, protocols);
  const inbox: AnyMsg[] = [];
  const waiters = new Set<{ predicate: (m: AnyMsg) => boolean; resolve: (m: AnyMsg) => void }>();

  ws.on('message', (buf) => {
    try {
      const msg = JSON.parse(String(buf));
      inbox.push(msg);
      for (const w of [...waiters]) {
        if (w.predicate(msg)) {
          waiters.delete(w);
          w.resolve(msg);
        }
      }
    } catch {
      /* ignore */
    }
  });

  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${name} WS open timeout`)), 15000);
    ws.once('open', () => {
      clearTimeout(timer);
      resolve();
    });
    ws.once('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
  await new Promise((r) => setTimeout(r, 300)); // let session.ready land

  return {
    ws,
    inbox,
    send(payload: AnyMsg) {
      ws.send(JSON.stringify(payload));
    },
    waitFor(predicate: (m: AnyMsg) => boolean, timeoutMs = 8000): Promise<AnyMsg | null> {
      const existing = inbox.find(predicate);
      if (existing) return Promise.resolve(existing);
      return new Promise((resolve) => {
        const entry = {
          predicate,
          resolve: (m: AnyMsg) => {
            clearTimeout(timer);
            resolve(m);
          },
        };
        const timer = setTimeout(() => {
          waiters.delete(entry);
          resolve(null);
        }, timeoutMs);
        waiters.add(entry);
      });
    },
    close() {
      try {
        ws.close(1000, 'done');
      } catch {
        /* ignore */
      }
    },
  };
}

describe.runIf(process.env.E2E === '1')('E2E happy path (M13)', () => {
  it('host creates room, viewer joins, sync + chat flow end-to-end', async () => {
    // 1. Two fresh users
    const host = await signup('h');
    const viewer = await signup('v');

    // 2. Host creates a room with a YouTube media item
    const room = await json('/api/rooms', {
      method: 'POST',
      token: host.token,
      body: {
        name: 'E2E Happy Path',
        maxParticipants: 10,
        privacy: 'public',
        mediaItem: {
          id: 'dQw4w9WgXcQ',
          title: 'E2E Video',
          // Было `${API_BASE}/api/media/youtube-player?...` — при запуске
          // против localhost это резалось SSRF-guard'ом (и правильно).
          // Реальный клиент шлёт публичный YouTube-URL (V4HomeViewLive.swift:871).
          streamURL: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          mediaType: 'video',
          source: 'youtube',
          videoId: 'dQw4w9WgXcQ',
        },
      },
    });
    expect(room.id).toBeTruthy();
    expect(room.code).toBeTruthy();

    // 3. Both join by code
    await json('/api/rooms/join', { method: 'POST', token: host.token, body: { code: room.code } });
    await json('/api/rooms/join', {
      method: 'POST',
      token: viewer.token,
      body: { code: room.code },
    });

    // 4. Realtime connect (sequential — parallel ticket handshakes race under load)
    const hostWS = await openClient(host.token, room.id, 'host');
    const viewerWS = await openClient(viewer.token, room.id, 'viewer');

    try {
      // 5. Host sends play — viewer must receive an ordered sync state
      hostWS.send({
        type: 'sync.command',
        protocolVersion: 2,
        roomId: room.id,
        actionId: randomUUID(),
        mediaId: 'dQw4w9WgXcQ',
        positionMs: 0,
        playing: true,
        rate: 1,
      });
      const sync = await viewerWS.waitFor(
        (m) =>
          (m.type === 'sync.state' || m.type === 'sync.state.snapshot') &&
          m.state?.playing === true,
      );
      expect(sync, 'viewer must receive playing sync.state').toBeTruthy();

      // 6. Host sends chat — viewer must receive the broadcast
      const text = `привет из e2e ${Date.now()}`;
      hostWS.send({
        type: 'chat.send',
        protocolVersion: 2,
        roomId: room.id,
        clientMessageId: randomUUID(),
        text,
      });
      const chat = await viewerWS.waitFor((m) => m.type === 'chat.broadcast' && m.text === text);
      expect(chat, 'viewer must receive chat.broadcast').toBeTruthy();
      expect(chat?.senderId).toBeTruthy();

      // 7. Pause lands too
      hostWS.send({
        type: 'sync.command',
        protocolVersion: 2,
        roomId: room.id,
        actionId: randomUUID(),
        mediaId: 'dQw4w9WgXcQ',
        positionMs: 5000,
        playing: false,
        rate: 1,
      });
      const pause = await viewerWS.waitFor(
        (m) => m.type === 'sync.state' && m.state?.playing === false,
      );
      expect(pause, 'viewer must receive paused sync.state').toBeTruthy();
    } finally {
      hostWS.close();
      viewerWS.close();
    }
  }, 60000);
});
