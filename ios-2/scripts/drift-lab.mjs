#!/usr/bin/env node
/**
 * Plink multi-client sync lag lab (protocol v2).
 *
 * Usage:
 *   node scripts/drift-lab.mjs
 *   VIEWERS=2 RUNS=10 node scripts/drift-lab.mjs
 */

import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';

const API = (process.env.API_BASE || 'https://plink-backend-production-ef31.up.railway.app').replace(/\/$/, '');
const VIEWERS = Number(process.env.VIEWERS || 2);
const RUNS = Number(process.env.RUNS || 10);
const WS_BASE = API.replace(/^http/, 'ws');

async function json(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${JSON.stringify(data)}`);
  return data;
}

async function signup(label) {
  const suffix = `${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  return json('/api/auth/signup', {
    method: 'POST',
    body: {
      email: `drift_${label}_${suffix}@plink.lab`,
      password: 'DriftLab123!',
      username: `d${label}${suffix}`.replace(/[^a-zA-Z0-9]/g, '').slice(0, 20),
    },
  });
}

async function openClient(token, roomId, name) {
  const t = await json('/api/realtime/ticket', {
    method: 'POST',
    token,
    body: { roomId },
  });
  const sub = t.protocol?.length ? t.protocol : ['plink.v2', `plink.ticket.${t.ticket}`];
  const ws = new WebSocket(`${WS_BASE}/ws/room/${roomId}`, sub);
  const pending = new Set();

  ws.on('message', (buf) => {
    try {
      const msg = JSON.parse(String(buf));
      if (msg.type === 'sync.state' || (msg.type === 'sync.state.snapshot' && msg.state)) {
        for (const p of [...pending]) {
          pending.delete(p);
          p.resolve({ msg, at: Date.now() });
        }
      }
    } catch { /* ignore */ }
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${name} WS open timeout`)), 15000);
    ws.once('open', () => { clearTimeout(timer); resolve(); });
    ws.once('error', (e) => { clearTimeout(timer); reject(e); });
    ws.once('close', (c, r) => {
      clearTimeout(timer);
      reject(new Error(`${name} closed ${c} ${r}`));
    });
  });

  // wait for session.ready a beat
  await new Promise((r) => setTimeout(r, 200));

  return {
    ws,
    waitSync(timeoutMs = 5000) {
      return new Promise((resolve) => {
        const entry = {
          resolve: (v) => {
            clearTimeout(timer);
            resolve(v);
          },
        };
        const timer = setTimeout(() => {
          pending.delete(entry);
          resolve(null);
        }, timeoutMs);
        pending.add(entry);
      });
    },
  };
}

async function main() {
  console.log(`Drift lab → ${API} viewers=${VIEWERS} runs=${RUNS}`);

  const hostAuth = await signup('h');
  const viewerAuths = [];
  for (let i = 0; i < VIEWERS; i++) viewerAuths.push(await signup(`v${i}`));

  const room = await json('/api/rooms', {
    method: 'POST',
    token: hostAuth.token,
    body: {
      name: 'Drift Lab',
      maxParticipants: 10,
      privacy: 'public',
      mediaItem: {
        id: 'dQw4w9WgXcQ',
        title: 'Drift Lab Video',
        streamURL: `${API}/api/media/youtube-player?id=dQw4w9WgXcQ`,
        mediaType: 'video',
        source: 'youtube',
        videoId: 'dQw4w9WgXcQ',
      },
    },
  });
  console.log(`Room ${room.code} id=${room.id}`);

  // Host + guests must be members
  await json('/api/rooms/join', { method: 'POST', token: hostAuth.token, body: { code: room.code } });
  for (const v of viewerAuths) {
    await json('/api/rooms/join', { method: 'POST', token: v.token, body: { code: room.code } });
  }

  // Sequential WS open (parallel open races tickets/handshake under load)
  const host = await openClient(hostAuth.token, room.id, 'host');
  const viewers = [];
  for (let i = 0; i < viewerAuths.length; i++) {
    viewers.push(await openClient(viewerAuths[i].token, room.id, `viewer${i}`));
  }

  // clock probes
  for (let i = 0; i < 3; i++) {
    host.ws.send(JSON.stringify({ type: 'clock.probe', protocolVersion: 2, clientSentMs: Date.now() }));
    await new Promise((r) => setTimeout(r, 150));
  }

  const latencies = [];
  for (let run = 0; run < RUNS; run++) {
    const waits = viewers.map((v) => v.waitSync(5000));
    const sentAt = Date.now();
    host.ws.send(JSON.stringify({
      type: 'sync.command',
      protocolVersion: 2,
      roomId: room.id,
      actionId: randomUUID(),
      mediaId: 'dQw4w9WgXcQ',
      positionMs: run * 5000 + 1000,
      playing: true,
      rate: 1,
    }));
    const results = await Promise.all(waits);
    for (const r of results) latencies.push(r ? r.at - sentAt : null);
    process.stdout.write('.');
    await new Promise((r) => setTimeout(r, 250));
  }
  console.log('');

  const ok = latencies.filter((x) => x != null).sort((a, b) => a - b);
  const pct = (p) => (ok.length ? ok[Math.min(ok.length - 1, Math.floor(ok.length * p))] : null);

  console.log('\n=== Results ===');
  console.log(`samples: ${ok.length}/${latencies.length} received`);
  if (ok.length) {
    console.log(`median lag: ${pct(0.5)} ms`);
    console.log(`p95 lag:    ${pct(0.95)} ms`);
    console.log(`max lag:    ${ok[ok.length - 1]} ms`);
    const pass = pct(0.5) < 500 && pct(0.95) < 1500;
    console.log(pass ? 'PASS (median <500ms, p95 <1.5s)' : 'FAIL vs drift targets');
  } else {
    console.log('FAIL — no sync.state received');
  }

  host.ws.close();
  viewers.forEach((v) => v.ws.close());
  process.exit(ok.length && pct(0.95) < 1500 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
