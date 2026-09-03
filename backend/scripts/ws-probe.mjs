// Отладочный зонд WS: показывает close-код и все сообщения за 4 секунды.
import WebSocket from 'ws';

const BASE = process.env.BASE ?? 'http://localhost:8091';
const WS_BASE = BASE.replace(/^http/, 'ws');
const tag = `wsp${Date.now().toString(36)}`;

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

const su = await api('/auth/signup', {
  method: 'POST',
  body: { email: `${tag}@test.plink`, password: `Passw0rd!${tag}`, username: `${tag}user` },
});
console.log('signup:', su.status);
const token = su.json.token;
const room = await api('/rooms', { method: 'POST', token, body: { name: `${tag} room` } });
const roomObj = room.json.room ?? room.json;
console.log('room:', room.status, roomObj.id);
const t = await api('/realtime/ticket', { method: 'POST', token, body: { roomId: roomObj.id } });
console.log(
  'ticket:',
  t.status,
  Object.keys(t.json ?? {}),
  'protocol field:',
  t.json?.protocol?.length,
);

const ws = new WebSocket(`${WS_BASE}/ws/room/${roomObj.id}`, [
  'plink.v2',
  `plink.ticket.${t.json.ticket}`,
]);
ws.on('open', () => console.log('OPEN, protocol selected:', JSON.stringify(ws.protocol)));
ws.on('message', (d) => console.log('MSG:', d.toString().slice(0, 200)));
ws.on('close', (code, reason) => console.log('CLOSE:', code, reason.toString()));
ws.on('error', (e) => console.log('ERROR:', e.message));

setTimeout(() => {
  console.log('sending sync.command');
  try {
    ws.send(
      JSON.stringify({
        type: 'sync.command',
        protocolVersion: 2,
        roomId: roomObj.id,
        actionId: `${tag}-a1`,
        mediaId: null,
        positionMs: 1000,
        playing: true,
        rate: 1,
      }),
    );
  } catch (e) {
    console.log('send failed:', e.message);
  }
}, 1000);
setTimeout(() => process.exit(0), 5000);
