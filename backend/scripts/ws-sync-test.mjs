// Фокусный тест WS-синхронизации: два клиента, хост шлёт sync.command,
// оба должны получить sync.state. Пользователи создаются напрямую в БД
// (signup ограничен 5/20мин), токены — через /auth/signin.
import { PrismaClient } from '@prisma/client';
import WebSocket from 'ws';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';

const BASE = process.env.BASE ?? 'http://localhost:8091';
const WS_BASE = BASE.replace(/^http/, 'ws');
const prisma = new PrismaClient();
const tag = `wst${Date.now().toString(36)}`;

async function api(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${BASE}/api${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function makeUser(suffix) {
  const email = `${tag}${suffix}@test.plink`;
  const password = `Passw0rd!${tag}`;
  const u = await prisma.user.create({
    data: { email, username: `${tag}${suffix}`, password: await bcrypt.hash(password, 10) },
  });
  const si = await api('/auth/signin', { method: 'POST', body: { email, password } });
  if (si.status !== 200) throw new Error(`signin: ${si.status}`);
  return { id: u.id, token: si.json.token };
}

async function wsConnect(label, roomId, token) {
  const t = await api('/realtime/ticket', { method: 'POST', token, body: { roomId } });
  if (t.status !== 200) throw new Error(`${label} ticket: ${t.status} ${JSON.stringify(t.json)}`);
  const ws = new WebSocket(`${WS_BASE}/ws/room/${roomId}`, [
    'plink.v2',
    `plink.ticket.${t.json.ticket}`,
  ]);
  const messages = [];
  ws.on('message', (d) => {
    const s = d.toString();
    console.log(`[${label}] MSG: ${s.slice(0, 160)}`);
    try {
      messages.push(JSON.parse(s));
    } catch {}
  });
  ws.on('close', (code, reason) => console.log(`[${label}] CLOSE: ${code} ${reason}`));
  ws.on('error', (e) => console.log(`[${label}] ERROR: ${e.message}`));
  await new Promise((res, rej) => {
    ws.once('open', res);
    ws.once('error', rej);
    setTimeout(() => rej(new Error('timeout')), 8000);
  });
  console.log(`[${label}] OPEN`);
  return { ws, messages };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

const host = await makeUser('h');
const guest = await makeUser('g');
const room = await api('/rooms', {
  method: 'POST',
  token: host.token,
  body: { name: `${tag} room` },
});
const roomObj = room.json.room ?? room.json;
console.log('room:', roomObj.id, 'code:', roomObj.code);
await api('/rooms/join', { method: 'POST', token: guest.token, body: { code: roomObj.code } });

const A = await wsConnect('host', roomObj.id, host.token);
const B = await wsConnect('guest', roomObj.id, guest.token);
// Как iOS-клиент: не шлём команды до session.ready — до него сервер ещё
// не навесил обработчик сообщений, и команда молча теряется.
for (let i = 0; i < 40; i++) {
  if (
    A.messages.some((m) => m.type === 'session.ready') &&
    B.messages.some((m) => m.type === 'session.ready')
  )
    break;
  await wait(250);
}
console.log('>>> host sends sync.command');
A.ws.send(
  JSON.stringify({
    type: 'sync.command',
    protocolVersion: 2,
    roomId: roomObj.id,
    actionId: crypto.randomUUID(),
    mediaId: null,
    positionMs: 5000,
    playing: true,
    rate: 1,
  }),
);
await wait(3000);
const okA = A.messages.some((m) => m.type === 'sync.state');
const okB = B.messages.some((m) => m.type === 'sync.state');
console.log(`\nИТОГ: host sync.state=${okA}, guest sync.state=${okB}`);
A.ws.close();
B.ws.close();
await prisma.user.deleteMany({ where: { username: { startsWith: tag } } });
await prisma.$disconnect();
process.exit(okA && okB ? 0 : 1);
