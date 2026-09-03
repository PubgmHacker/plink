// Install-free watch page for /w/:code (YouTube + VK + Rutube).
// Inline JS only (CSP nonce) — no external <script src>. YouTube player iframe is
// same-origin GET /api/media/youtube-player; VK/Rutube use official embed hosts.

import { extractYouTubeId } from '../services/streamExtractor.js';

export type WebWatchTarget =
  | { kind: 'youtube'; playerSrc: string; id: string }
  | { kind: 'rutube'; playerSrc: string; id: string }
  | { kind: 'vk'; playerSrc: string; id: string };

export function webWatchTargetFromMediaItem(raw: string | null | undefined): WebWatchTarget | null {
  const yt = youtubeIdFromMediaItem(raw);
  if (yt) {
    return {
      kind: 'youtube',
      id: yt,
      playerSrc: `/api/media/youtube-player?id=${encodeURIComponent(yt)}&chrome=youtube`,
    };
  }
  if (!raw) return null;
  let stream = raw;
  let videoId = '';
  if (raw.trim().startsWith('{')) {
    try {
      const m = JSON.parse(raw) as { streamURL?: unknown; videoId?: unknown; url?: unknown };
      if (typeof m.streamURL === 'string') stream = m.streamURL;
      else if (typeof m.url === 'string') stream = m.url;
      if (typeof m.videoId === 'string') videoId = m.videoId;
    } catch {
      /* ignore */
    }
  }

  const rutube = extractRutubeId(stream) || (videoId.length >= 8 ? videoId : '');
  if (rutube && (stream.includes('rutube.ru') || /^[a-f0-9]{32}$/i.test(rutube))) {
    return {
      kind: 'rutube',
      id: rutube,
      playerSrc: `https://rutube.ru/play/embed/${encodeURIComponent(rutube)}`,
    };
  }

  const vk = extractVkEmbed(stream, videoId);
  if (vk) return vk;
  return null;
}

function extractRutubeId(stream: string): string | null {
  const m = stream.match(/rutube\.ru\/(?:video|play\/embed)\/([a-zA-Z0-9]{8,32})/);
  return m ? m[1] : null;
}

function extractVkEmbed(stream: string, videoId: string): WebWatchTarget | null {
  if (stream.includes('video_ext.php')) {
    return { kind: 'vk', id: videoId || 'vk', playerSrc: stream };
  }
  const fromPath = stream.match(/vk\.com\/video(-?\d+)_(\d+)/);
  const fromId = videoId.match(/^(-?\d+)_(\d+)$/);
  const pair = fromPath || fromId;
  if (!pair) return null;
  const oid = pair[1];
  const id = pair[2];
  return {
    kind: 'vk',
    id: `${oid}_${id}`,
    playerSrc: `https://vk.com/video_ext.php?oid=${encodeURIComponent(oid)}&id=${encodeURIComponent(id)}&hd=2`,
  };
}

/** Parse room.mediaItem JSON/string into an 11-char YouTube id, or null. */
export function youtubeIdFromMediaItem(raw: string | null | undefined): string | null {
  if (!raw || typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith('{')) {
    try {
      const m = JSON.parse(trimmed) as {
        videoId?: unknown;
        id?: unknown;
        streamURL?: unknown;
        source?: unknown;
        url?: unknown;
      };
      const vid = typeof m.videoId === 'string' ? m.videoId : '';
      if (/^[\w-]{11}$/.test(vid)) return vid;
      const id = typeof m.id === 'string' ? m.id : '';
      if (
        /^[\w-]{11}$/.test(id) &&
        (m.source === 'youtube' || m.source == null || m.source === '')
      ) {
        return id;
      }
      const stream =
        typeof m.streamURL === 'string' ? m.streamURL : typeof m.url === 'string' ? m.url : '';
      if (stream) {
        const fromUrl = extractYouTubeId(stream);
        if (fromUrl) return fromUrl;
      }
    } catch {
      /* fall through */
    }
  }

  return extractYouTubeId(trimmed);
}

export function mediaTitleFromMediaItem(raw: string | null | undefined): string | null {
  if (!raw) return null;
  if (!raw.trim().startsWith('{')) return raw.slice(0, 120);
  try {
    const m = JSON.parse(raw) as { title?: unknown };
    return typeof m.title === 'string' && m.title.trim() ? m.title.trim().slice(0, 120) : null;
  } catch {
    return null;
  }
}

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export type WatchPageOpts = {
  code: string;
  roomName: string;
  mediaTitle: string | null;
  target: WebWatchTarget;
  nonce: string;
  publicOrigin: string;
};

export function webWatchPageHTML(opts: WatchPageOpts): string {
  const title = `${opts.roomName} — смотреть в браузере · Plink`;
  const playerSrc = opts.target.playerSrc;
  const kind = opts.target.kind;
  const appLink = `plink://r/${opts.code}`;
  const installLink = `/r/${encodeURIComponent(opts.code)}`;

  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="Смотри вместе в браузере — без установки. Синхрон с хостом Plink.">
<link rel="canonical" href="${esc(opts.publicOrigin)}/w/${esc(opts.code)}">
<style>
  :root { color-scheme: dark; --bg:#0b0c10; --card:#14161d; --ink:#f2f4f8; --muted:#9aa3b2; --accent:#6ea8ff; --line:rgba(255,255,255,.08); --danger:#ff6b6b; }
  * { box-sizing: border-box; }
  html, body { margin:0; height:100%; background:var(--bg); color:var(--ink); font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
  body { display:flex; flex-direction:column; min-height:100%; }
  header { display:flex; align-items:center; justify-content:space-between; gap:12px; padding:12px 16px; border-bottom:1px solid var(--line); }
  .brand { font-weight:800; letter-spacing:.02em; }
  .meta { color:var(--muted); font-size:13px; }
  .stage { flex:1; display:flex; flex-direction:column; min-height:0; }
  .player-wrap { position:relative; width:100%; background:#000; aspect-ratio:16/9; max-height:min(70vh, 720px); }
  .player-wrap iframe { position:absolute; inset:0; width:100%; height:100%; border:0; }
  .panel { padding:14px 16px 28px; display:flex; flex-direction:column; gap:10px; }
  .status { font-size:13px; color:var(--muted); min-height:1.2em; }
  .status.err { color:var(--danger); }
  .row { display:flex; flex-wrap:wrap; gap:8px; }
  a.btn, button.btn { appearance:none; border:0; border-radius:12px; padding:11px 14px; font-weight:700; font-size:14px; text-decoration:none; cursor:pointer; display:inline-flex; align-items:center; gap:8px; }
  .btn-primary { background:var(--accent); color:#0b0c10; }
  .btn-ghost { background:var(--card); color:var(--ink); border:1px solid var(--line); }
  h1 { font-size:18px; margin:0; line-height:1.3; }
  .hint { font-size:12px; color:var(--muted); line-height:1.45; }
</style>
</head>
<body>
  <header>
    <div class="brand">Plink</div>
    <div class="meta">код ${esc(opts.code)}</div>
  </header>
  <div class="stage">
    <div class="player-wrap">
      <iframe id="yt" title="${esc(kind === 'youtube' ? 'YouTube' : kind === 'vk' ? 'VK' : 'Rutube')}" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen referrerpolicy="strict-origin-when-cross-origin" src="${esc(playerSrc)}"></iframe>
    </div>
    <div class="panel">
      <h1>${esc(opts.roomName)}</h1>
      ${opts.mediaTitle ? `<div class="meta">${esc(opts.mediaTitle)}</div>` : ''}
      <div id="status" class="status" role="status">Подключаемся…</div>
      <div class="row">
        <a class="btn btn-primary" href="${esc(appLink)}">Открыть в приложении</a>
        <a class="btn btn-ghost" href="${esc(installLink)}">Установка / код</a>
      </div>
      <p class="hint">${
        kind === 'youtube'
          ? 'Гость в браузере следует за хостом. Пауза и перемотка — у ведущего. Кинотеатры — в приложении («ваш экран»).'
          : 'VK и Rutube в браузере открываются официальным плеером. Точный синхрон — в приложении Plink.'
      }</p>
    </div>
  </div>
  <script nonce="${opts.nonce}">
  (function () {
    var CODE = ${JSON.stringify(opts.code)};
    var KIND = ${JSON.stringify(kind)};
    var PLAYER_SRC = ${JSON.stringify(playerSrc)};
    var statusEl = document.getElementById('status');
    var iframe = document.getElementById('yt');
    var token = null;
    var roomId = null;
    var ws = null;
    var lastSeq = -1;
    var playerReady = false;
    var pendingState = null;

    function setStatus(text, isErr) {
      statusEl.textContent = text;
      statusEl.className = isErr ? 'status err' : 'status';
    }

    function api(path, opts) {
      opts = opts || {};
      var headers = { 'Content-Type': 'application/json', 'Accept': 'application/json' };
      if (token) headers.Authorization = 'Bearer ' + token;
      return fetch(path, {
        method: opts.method || 'GET',
        headers: headers,
        body: opts.body ? JSON.stringify(opts.body) : undefined,
        credentials: 'same-origin',
      }).then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (body) {
          if (!res.ok) {
            var err = new Error((body && (body.error || body.message)) || ('HTTP ' + res.status));
            err.status = res.status;
            err.body = body;
            throw err;
          }
          return body;
        });
      });
    }

    function playerWin() {
      try { return iframe.contentWindow; } catch (e) { return null; }
    }

    function cmd(name, payload) {
      var w = playerWin();
      if (!w) return;
      try {
        if (typeof w.plinkCmd === 'function') w.plinkCmd(name, payload || {});
        else if (name === 'play' && typeof w.plinkPlay === 'function') w.plinkPlay();
        else if (name === 'pause' && typeof w.plinkPause === 'function') w.plinkPause();
        else if (name === 'seek' && typeof w.plinkSeek === 'function') w.plinkSeek((payload && payload.seconds) || 0);
      } catch (e) {}
    }

    function applyState(state) {
      if (!state) return;
      pendingState = state;
      if (KIND !== 'youtube') {
        setStatus(state.playing ? 'Хост смотрит · плеер в браузере без точного seek' : 'Хост на паузе');
        return;
      }
      if (!playerReady) return;
      var pos = (state.positionMs || 0) / 1000;
      if (state.playing && state.effectiveAtServerMs) {
        pos += Math.max(0, (Date.now() - state.effectiveAtServerMs) / 1000) * (state.rate || 1);
      }
      cmd('seek', { seconds: Math.max(0, pos) });
      if (state.playing) cmd('play'); else cmd('pause');
      setStatus(state.playing ? 'В синхроне · смотрим' : 'На паузе у хоста');
    }

    window.addEventListener('message', function (ev) {
      if (ev.source !== iframe.contentWindow) return;
      var data = ev.data;
      if (!data || typeof data !== 'object') return;
      if (data.event === 'ready' || data.type === 'ready') {
        playerReady = true;
        if (pendingState) applyState(pendingState);
      }
    });

    function wsUrl(id) {
      var proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      return proto + '//' + location.host + '/ws/room/' + id;
    }

    function connectWs(ticketProtocols) {
      return new Promise(function (resolve, reject) {
        var sock = new WebSocket(wsUrl(roomId), ticketProtocols);
        var opened = false;
        var timer = setTimeout(function () {
          if (!opened) {
            try { sock.close(); } catch (e) {}
            reject(new Error('WebSocket timeout'));
          }
        }, 15000);
        sock.onopen = function () {
          opened = true;
          clearTimeout(timer);
          resolve(sock);
        };
        sock.onerror = function () {
          clearTimeout(timer);
          if (!opened) reject(new Error('WebSocket error'));
        };
      });
    }

    function onMessage(raw) {
      var msg;
      try { msg = JSON.parse(raw.data); } catch (e) { return; }
      if (!msg || !msg.type) return;
      if (msg.type === 'session.ready' || msg.type === 'session.hello') {
        ws.send(JSON.stringify({
          type: 'sync.state.request',
          protocolVersion: 2,
          roomId: roomId,
          afterSeq: 0
        }));
        return;
      }
      if (msg.type === 'sync.state' || msg.type === 'sync.state.snapshot') {
        var state = msg.state;
        if (!state) return;
        if (typeof state.seq === 'number' && state.seq < lastSeq) return;
        if (typeof state.seq === 'number') lastSeq = state.seq;
        applyState(state);
      }
    }

    function joinRoom(password) {
      var body = { code: CODE };
      if (password) body.password = password;
      return api('/api/rooms/join', { method: 'POST', body: body });
    }

    function boot() {
      setStatus('Входим как гость…');
      return api('/api/auth/guest', { method: 'POST', body: { roomCode: CODE } })
        .then(function (auth) {
          token = auth.token;
          setStatus('Входим в комнату…');
          return joinRoom(null);
        })
        .catch(function (err) {
          var body = err && err.body;
          if (body && body.code === 'ROOM_PASSWORD_REQUIRED') {
            var pw = window.prompt('Комната с паролем. Введи пароль:');
            if (!pw) throw err;
            return joinRoom(pw);
          }
          throw err;
        })
        .then(function (room) {
          roomId = room.id;
          setStatus('Билет на синхрон…');
          return api('/api/realtime/ticket', { method: 'POST', body: { roomId: roomId } });
        })
        .then(function (t) {
          var protocols = (t.protocol && t.protocol.length)
            ? t.protocol
            : ['plink.v2', 'plink.ticket.' + t.ticket];
          setStatus('Подключаем синхрон…');
          return connectWs(protocols);
        })
        .then(function (sock) {
          ws = sock;
          ws.onmessage = onMessage;
          ws.onclose = function () { setStatus('Связь оборвалась — обновите страницу', true); };
          setStatus('Ждём состояние хоста…');
          try {
            ws.send(JSON.stringify({
              type: 'sync.state.request',
              protocolVersion: 2,
              roomId: roomId,
              afterSeq: 0
            }));
          } catch (e) {}
        })
        .catch(function (err) {
          var body = err && err.body;
          if (body && body.code === 'FRIENDS_ONLY') {
            setStatus('Комната только для друзей хоста — открой в приложении Plink', true);
            return;
          }
          if (body && body.code === 'ROOM_PASSWORD_REQUIRED') {
            setStatus('Нужен пароль комнаты', true);
            return;
          }
          setStatus((err && err.message) || 'Не удалось войти', true);
        });
    }

    // Give the iframe a tick to boot before we hammer plinkCmd.
    setTimeout(function () { playerReady = true; if (pendingState) applyState(pendingState); }, 2500);
    boot();
  })();
  </script>
</body>
</html>`;
}

export function webWatchUnsupportedHTML(opts: {
  code: string;
  roomName: string;
  reason: string;
  nonce: string;
  publicOrigin: string;
}): string {
  const install = `/r/${encodeURIComponent(opts.code)}`;
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(opts.roomName)} — Plink</title>
<style>
  body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0c10;color:#f2f4f8;font-family:system-ui,sans-serif;padding:24px}
  .card{max-width:420px;background:#14161d;border:1px solid rgba(255,255,255,.08);border-radius:18px;padding:22px}
  h1{font-size:20px;margin:0 0 10px} p{color:#9aa3b2;line-height:1.45;font-size:14px}
  a{display:inline-block;margin-top:14px;background:#6ea8ff;color:#0b0c10;text-decoration:none;font-weight:700;padding:11px 14px;border-radius:12px}
</style>
</head>
<body>
  <div class="card">
    <h1>В браузере — YouTube, VK и Rutube</h1>
    <p>${esc(opts.reason)}</p>
    <a href="${esc(install)}">Открыть страницу комнаты</a>
  </div>
</body>
</html>`;
}
