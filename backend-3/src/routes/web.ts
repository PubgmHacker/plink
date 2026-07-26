// web.ts — Plink M39 (v2)
//
// Что было не так в v1 и почему это была дыра:
//   Лендинги комнаты и профиля подставляли код комнаты и имя пользователя внутрь
//   <script>…</script> без экранирования. Любой человек мог создать комнату
//   с вредоносным кодом в названии и разослать ссылку.
//
// Решение: скриптов на лендингах нет вообще. Переход в приложение — через Universal Links
// и обычную ссылку. Плюс строгие регулярки валидации и CSP `default-src 'none'`.

import type { FastifyInstance, FastifyReply } from 'fastify'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient()

const ROOM_CODE_RE = /^[A-Z0-9]{4,12}$/
const USERNAME_RE = /^[a-zA-Z0-9_.]{3,32}$/

const PUBLIC_ORIGIN = process.env.PUBLIC_ORIGIN ?? 'https://plink.app'
const APP_STORE_URL = process.env.APP_STORE_URL ?? 'https://apps.apple.com/app/id0000000000'
const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID ?? 'TEAMID0000'
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.plink.app'

// Экранирование всего, что пришло извне. Без исключений.
function escHTML(input: unknown): string {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function escXML(input: unknown): string {
  return escHTML(input)
}

function securityHeaders(reply: FastifyReply) {
  reply.header('Content-Security-Policy',
    "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'")
  reply.header('X-Content-Type-Options', 'nosniff')
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin')
  reply.header('X-Frame-Options', 'DENY')
  reply.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()')
}

function appStoreNumericID(): string {
  const match = APP_STORE_URL.match(/id(\d+)/)
  return match ? match[1] : '0000000000'
}

// Афиша для превью в мессенджерах. Генерится на лету, без внешних сервисов.
function ogSVG(title: string, subtitle: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#071214"/>
      <stop offset="100%" stop-color="#0d2226"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <circle cx="1010" cy="140" r="210" fill="#19e0c0" opacity="0.13"/>
  <text x="80" y="270" font-family="-apple-system,Helvetica,Arial" font-size="64" font-weight="700" fill="#eafaf7">${escXML(title)}</text>
  <text x="80" y="340" font-family="-apple-system,Helvetica,Arial" font-size="32" fill="#8fb3ae">${escXML(subtitle)}</text>
  <text x="80" y="550" font-family="-apple-system,Helvetica,Arial" font-size="28" font-weight="600" fill="#19e0c0">Plink — смотрите вместе</text>
</svg>`
}

async function sendOG(reply: FastifyReply, title: string, subtitle: string) {
  const svg = ogSVG(title, subtitle)
  reply.header('Cache-Control', 'public, max-age=3600')
  try {
    // sharp опционален: если его нет — отдаём SVG, превью всё равно работает.
    const { default: sharp } = await import('sharp')
    const png = await sharp(Buffer.from(svg)).png().toBuffer()
    return reply.type('image/png').send(png)
  } catch {
    return reply.type('image/svg+xml').send(svg)
  }
}

function landing(opts: {
  title: string
  heading: string
  subheading: string
  ogImage: string
  canonical: string
}): string {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escHTML(opts.title)}</title>
<link rel="canonical" href="${escHTML(opts.canonical)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${escHTML(opts.title)}">
<meta property="og:description" content="${escHTML(opts.subheading)}">
<meta property="og:image" content="${escHTML(opts.ogImage)}">
<meta property="og:url" content="${escHTML(opts.canonical)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=${appStoreNumericID()}">
<style>
  :root { color-scheme: dark }
  body { margin:0; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background:#071214; color:#eafaf7; display:flex; min-height:100vh;
         align-items:center; justify-content:center; text-align:center; padding:24px }
  .card { max-width:440px }
  h1 { font-size:30px; margin:0 0 10px; letter-spacing:-.5px }
  p { color:#8fb3ae; margin:0 0 26px }
  a.btn { display:inline-block; background:#19e0c0; color:#04201c; text-decoration:none;
          font-weight:700; padding:15px 30px; border-radius:14px }
  a.alt { display:block; margin-top:16px; color:#8fb3ae; font-size:14px }
</style>
</head>
<body>
  <div class="card">
    <h1>${escHTML(opts.heading)}</h1>
    <p>${escHTML(opts.subheading)}</p>
    <a class="btn" href="${escHTML(APP_STORE_URL)}">Открыть в Plink</a>
    <a class="alt" href="${escHTML(PUBLIC_ORIGIN)}">Что такое Plink?</a>
  </div>
</body>
</html>`
}

export async function webRoutes(fastify: FastifyInstance) {
  // —— Universal Links ——
  fastify.get('/.well-known/apple-app-site-association', async (_req, reply) => {
    reply.header('Content-Type', 'application/json')
    reply.header('Cache-Control', 'public, max-age=3600')
    return {
      applinks: {
        details: [
          {
            appIDs: [`${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}`],
            components: [
              { '/': '/r/*', comment: 'Комнаты' },
              { '/': '/u/*', comment: 'Профили' },
            ],
          },
        ],
      },
      webcredentials: { apps: [`${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}`] },
    }
  })

  // —— Лендинг комнаты ——
  fastify.get<{ Params: { code: string } }>('/r/:code', async (req, reply) => {
    securityHeaders(reply)
    const code = String(req.params.code ?? '').toUpperCase()

    if (!ROOM_CODE_RE.test(code)) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        title: 'Plink — комната не найдена',
        heading: 'Комната не найдена',
        subheading: 'Ссылка устарела или введена с ошибкой.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/r/${encodeURIComponent(code)}`,
      }))
    }

    const room = await prisma.room.findFirst({
      where: { code, hidden: false },
      select: { name: true, mediaTitle: true },
    })

    if (!room) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        title: 'Plink — комната закрыта',
        heading: 'Комната закрыта',
        subheading: 'Но вы можете создать свою за пару секунд.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/r/${code}`,
      }))
    }

    const name = room.name || 'Комната Plink'
    return reply.type('text/html; charset=utf-8').send(landing({
      title: `${name} — Plink`,
      heading: name,
      subheading: room.mediaTitle
        ? `Сейчас смотрят: ${room.mediaTitle}. Присоединяйтесь — кадр в кадр.`
        : 'Присоединяйтесь к просмотру — кадр в кадр.',
      ogImage: `${PUBLIC_ORIGIN}/og/r/${code}.png`,
      canonical: `${PUBLIC_ORIGIN}/r/${code}`,
    }))
  })

  // —— Лендинг профиля ——
  fastify.get<{ Params: { username: string } }>('/u/:username', async (req, reply) => {
    securityHeaders(reply)
    const username = String(req.params.username ?? '')

    if (!USERNAME_RE.test(username)) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        title: 'Plink — профиль не найден',
        heading: 'Профиль не найден',
        subheading: 'Проверьте ссылку.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/u/${encodeURIComponent(username)}`,
      }))
    }

    const user = await prisma.user.findFirst({
      where: { username, deletedAt: null, shadowbanned: false },
      select: { displayName: true, username: true, bio: true },
    })

    if (!user) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        title: 'Plink — профиль не найден',
        heading: 'Профиль не найден',
        subheading: 'Возможно, аккаунт удалён.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/u/${username}`,
      }))
    }

    const display = user.displayName || user.username
    return reply.type('text/html; charset=utf-8').send(landing({
      title: `${display} в Plink`,
      heading: display,
      subheading: user.bio || 'Смотрите вместе в Plink.',
      ogImage: `${PUBLIC_ORIGIN}/og/u/${username}.png`,
      canonical: `${PUBLIC_ORIGIN}/u/${username}`,
    }))
  })

  // —— Афиши ——
  fastify.get<{ Params: { code: string } }>('/og/r/:code.png', async (req, reply) => {
    const code = String(req.params.code ?? '').replace(/\.png$/, '').toUpperCase()
    if (!ROOM_CODE_RE.test(code)) return sendOG(reply, 'Plink', 'Смотрите вместе')
    const room = await prisma.room.findFirst({
      where: { code, hidden: false },
      select: { name: true, mediaTitle: true },
    })
    return sendOG(reply, room?.name || 'Комната Plink',
      room?.mediaTitle || 'Присоединяйтесь к просмотру')
  })

  fastify.get<{ Params: { username: string } }>('/og/u/:username.png', async (req, reply) => {
    const username = String(req.params.username ?? '').replace(/\.png$/, '')
    if (!USERNAME_RE.test(username)) return sendOG(reply, 'Plink', 'Смотрите вместе')
    const user = await prisma.user.findFirst({
      where: { username, deletedAt: null, shadowbanned: false },
      select: { displayName: true, username: true },
    })
    return sendOG(reply, user?.displayName || user?.username || 'Plink',
      'Смотрите вместе в Plink')
  })

  fastify.get('/og/default.png', async (_req, reply) =>
    sendOG(reply, 'Plink', 'Смотрите вместе — кадр в кадр'))
}
