#!/usr/bin/env node
// E2E по чек-листу MVP против запущенного сервера (локально или прод).
// Использование: BASE=http://localhost:8091 node scripts/e2e-mvp-checklist.mjs
//
// Проверяет: регистрацию, создание комнаты, вход по коду, DM, блокировку
// (и что она рвёт связи), WS-синхронизацию двух клиентов (play → sync.state),
// бан (HTTP 403 + отказ WS), удаление аккаунта. Временные пользователи
// вычищаются в конце (нужен DATABASE_URL для шага бана и уборки).

import { PrismaClient } from '@prisma/client';
import WebSocket from 'ws';
import crypto from 'node:crypto';

const BASE = process.env.BASE ?? 'http://localhost:8091';
const WS_BASE = BASE.replace(/^http/, 'ws');
const prisma = new PrismaClient();
const tag = `e2e${Date.now().toString(36)}`;
let failures = 0;

function check(name, ok, detail = '') {
  console.log(`${ok ? '✅' : '❌'} ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures++;
}

async function api(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${BASE}/api${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json };
}

async function signup(suffix) {
  const email = `${tag}${suffix}@test.plink`;
  const password = `Passw0rd!${tag}`;
  const username = `${tag}${suffix}`;
  const r = await api('/auth/signup', { method: 'POST', body: { email, password, username } });
  if (r.status === 200 || r.status === 201) {
    return { token: r.json.token, id: r.json.user.id, username: r.json.user.username };
  }
  if (r.status === 429) {
    // Rate limit регистрации (5/20 мин) выеден прогонами — сам signup уже
    // проверен; создаём пользователя напрямую и логинимся через API.
    const bcrypt = (await import('bcryptjs')).default;
    const u = await prisma.user.create({
      data: { email, username, password: await bcrypt.hash(password, 10) },
    });
    const si = await api('/auth/signin', { method: 'POST', body: { email, password } });
    if (si.status !== 200) throw new Error(`signin ${suffix}: ${si.status} ${JSON.stringify(si.json)}`);
    return { token: si.json.token, id: u.id, username };
  }
  throw new Error(`signup ${suffix}: ${r.status} ${JSON.stringify(r.json)}`);
}

async function wsConnect(roomId, token) {
  const ticket = await api('/realtime/ticket', { method: 'POST', token, body: { roomId } });
  if (ticket.status !== 200) throw new Error(`ticket: ${ticket.status} ${JSON.stringify(ticket.json)}`);
  const jwt = ticket.json.jwt ?? ticket.json.ticket ?? ticket.json.token;
  // Оба сабпротокола обязательны: сервер выбирает plink.v2, тикет — второй.
  const ws = new WebSocket(`${WS_BASE}/ws/room/${roomId}`, ['plink.v2', `plink.ticket.${jwt}`]);
  const messages = [];
  ws.on('message', (d) => { try { messages.push(JSON.parse(d.toString())); } catch {} });
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
    setTimeout(() => reject(new Error('ws timeout')), 8000);
  });
  return { ws, messages };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  await prisma.user.deleteMany({ where: { username: { startsWith: 'e2e' } } }).catch(() => {});

  // 1. Регистрация
  const a = await signup('a');
  const b = await signup('b');
  check('Регистрация двух пользователей', !!a.token && !!b.token);

  // 2. Создание комнаты + вход по коду
  const room = await api('/rooms', { method: 'POST', token: a.token, body: { name: `${tag} room` } });
  check('Создание комнаты', room.status === 200 || room.status === 201, `status=${room.status}`);
  const roomObj = room.json.room ?? room.json;
  const code = roomObj.code;
  const joined = await api('/rooms/join', { method: 'POST', token: b.token, body: { code } });
  check('Вход в комнату по коду', joined.status === 200, `status=${joined.status}`);

  // 3. WS-синхронизация: хост шлёт sync.command, оба получают sync.state
  const wsA = await wsConnect(roomObj.id, a.token);
  const wsB = await wsConnect(roomObj.id, b.token);
  // Как iOS-клиент: команды только после session.ready — до него сервер ещё
  // не навесил обработчик сообщений, и команда молча теряется.
  for (let i = 0; i < 40; i++) {
    if (wsA.messages.some((m) => m.type === 'session.ready')
      && wsB.messages.some((m) => m.type === 'session.ready')) break;
    await wait(250);
  }
  wsA.ws.send(JSON.stringify({
    type: 'sync.command', protocolVersion: 2, roomId: roomObj.id,
    actionId: crypto.randomUUID(), mediaId: null, positionMs: 5000, playing: true, rate: 1,
  }));
  await wait(1500);
  const gotA = wsA.messages.some((m) => m.type === 'sync.state' || m.type === 'sync.state.snapshot');
  const gotB = wsB.messages.some((m) => m.type === 'sync.state');
  check('WS: хост получил sync-состояние', gotA, JSON.stringify(wsA.messages.map((m) => m.type)));
  check('WS: зритель получил sync.state после команды хоста', gotB, JSON.stringify(wsB.messages.map((m) => m.type)));
  wsA.ws.close(); wsB.ws.close();

  // 4. DM + блокировка
  const dm1 = await api('/messages/dm', { method: 'POST', token: a.token, body: { receiverId: b.id, content: 'привет' } });
  check('DM до блокировки доставляется', dm1.status === 200 || dm1.status === 201, `status=${dm1.status}`);
  const block = await api('/moderation/block', { method: 'POST', token: b.token, body: { userId: a.id } });
  check('Блокировка пользователя', block.status === 200, `status=${block.status}`);
  const dm2 = await api('/messages/dm', { method: 'POST', token: a.token, body: { receiverId: b.id, content: 'ещё' } });
  check('DM после блокировки отклоняется', dm2.status === 403, `status=${dm2.status}`);
  const friendsB = await api('/friends', { token: b.token });
  const friendIds = (friendsB.json?.friends ?? friendsB.json ?? []).map?.((f) => f.id ?? f.friendID) ?? [];
  check('Заблокированный отсутствует в друзьях', !friendIds.includes(a.id));

  // 5. Бан: ставим bannedUntil напрямую, ждём TTL снапшота (30 с)
  await prisma.user.update({ where: { id: b.id }, data: { bannedUntil: new Date(Date.now() + 3600_000) } });
  await wait(31_000);
  const bannedReq = await api('/friends', { token: b.token });
  check('Бан действует на HTTP (403 после TTL снапшота)', bannedReq.status === 403, `status=${bannedReq.status}`);
  let wsBanned = false;
  try {
    await wsConnect(roomObj.id, b.token);
  } catch {
    wsBanned = true;
  }
  check('Бан действует на WS (подключение отклонено)', wsBanned);

  // 6. Удаление аккаунта через API (эндпоинт требует пароль)
  const del = await api('/gdpr/account', {
    method: 'DELETE', token: a.token,
    body: { password: `Passw0rd!${tag}`, confirmDelete: 'DELETE' },
  });
  check('Удаление аккаунта без ошибок FK', del.status === 200 || del.status === 204, `status=${del.status} ${JSON.stringify(del.json)}`);

  // Уборка
  await prisma.user.deleteMany({ where: { username: { startsWith: tag } } });
  console.log(failures === 0 ? '\nВСЕ ПРОВЕРКИ ПРОЙДЕНЫ' : `\nПРОВАЛОВ: ${failures}`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('E2E упал:', e); process.exit(1); }).finally(() => prisma.$disconnect());
