// web.ts — Plink M39 (v3: лендинг-установщик)
//
// Что было не так в v1 и почему это была дыра:
//   Лендинги комнаты и профиля подставляли код комнаты и имя пользователя внутрь
//   <script>…</script> без экранирования. Любой человек мог создать комнату
//   с вредоносным кодом в названии и разослать ссылку.
//
// v2 решал это полным отказом от скриптов. v3 возвращает ОДИН маленький скрипт
// (авто-открытие приложения + копирование кода), но безопасно:
//   • в скрипт попадает только код комнаты, прошедший ROOM_CODE_RE, и только
//     через JSON.stringify — пользовательские строки в JS не попадают вовсе;
//   • CSP разрешает скрипт только по одноразовому nonce (unsafe-inline нет);
//   • весь пользовательский текст в разметке по-прежнему через escHTML.

import crypto from 'node:crypto'
import QRCode from 'qrcode'
import type { FastifyInstance, FastifyReply } from 'fastify'
import { prisma } from '../config/db.js'
import { WEB_PLANS, webPayConfigured } from './webpay.js'
import {
  mediaTitleFromMediaItem,
  webWatchPageHTML,
  webWatchTargetFromMediaItem,
  webWatchUnsupportedHTML,
} from '../web/watchPage.js'
import { PRIVACY, SUPPORT_EMAIL, TERMS, type LegalDocument } from '../web/legal.js'

const ROOM_CODE_RE = /^[A-Z0-9]{4,12}$/
const USERNAME_RE = /^[a-zA-Z0-9_.]{3,32}$/

const PUBLIC_ORIGIN = process.env.PUBLIC_ORIGIN ?? 'https://plink.app'
const APP_STORE_URL = process.env.APP_STORE_URL ?? 'https://apps.apple.com/app/id0000000000'
// До релиза в App Store кнопка установки ведёт в TestFlight (если задан).
const TESTFLIGHT_URL = process.env.TESTFLIGHT_URL ?? ''
const ANDROID_STORE_URL = process.env.ANDROID_STORE_URL ?? ''
const INSTALL_URL = TESTFLIGHT_URL || APP_STORE_URL
// Дефолты были заглушками (TEAMID0000 / com.plink.app),
// из-за чего AASA отдавал несуществующий appID и universal links не работали.
// Реальные значения — DEVELOPMENT_TEAM из project.yml и bundle id приложения
// (тот же дефолт, что в billing.ts).
const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID ?? '2QAMUC4Z4P'
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.syncwatch.plink'

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

// Инлайн SVG-иконки (по мотивам Lucide, ISC) — без эмодзи и внешних хостов.
const ICON_PATHS: Record<string, string> = {
  play: '<polygon points="7 4 20 12 7 20 7 4"/>',
  timer: '<line x1="10" y1="2" x2="14" y2="2"/><line x1="12" y1="14" x2="15" y2="11"/><circle cx="12" cy="14" r="8"/>',
  chat: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
  spark: '<path d="M12 2l1.9 5.7a2 2 0 0 0 1.4 1.4L21 11l-5.7 1.9a2 2 0 0 0-1.4 1.4L12 20l-1.9-5.7a2 2 0 0 0-1.4-1.4L3 11l5.7-1.9a2 2 0 0 0 1.4-1.4Z"/>',
  layers: '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  copy: '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
}

/// Пословный blur-in для дисплей-заголовков (анимация — CSS .bw).
function blurWords(text: string, startDelay = 0): string {
  return text.split(' ').map((w, i) =>
    `<span class="bw" style="--d:${(startDelay + i) * 0.1}s">${escHTML(w)}</span>`
  ).join('')
}

function icon(name: keyof typeof ICON_PATHS, size = 18): string {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON_PATHS[name]}</svg>`
}

function securityHeaders(
  reply: FastifyReply,
  scriptNonce?: string,
  allowConnect = false,
  /** /w/:code — fetch API + WS + player iframe (YouTube same-origin, VK/Rutube official) */
  watchMode = false,
) {
  const scriptSrc = scriptNonce ? `script-src 'nonce-${scriptNonce}'; ` : ''
  // connect-src: /plus (webpay) и /w (guest join + realtime ticket + WS).
  const connectSrc = allowConnect || watchMode
    ? "connect-src 'self' wss: ws:; "
    : ''
  const frameSrc = watchMode
    ? "frame-src 'self' https://vk.com https://www.vk.com https://rutube.ru https://www.rutube.ru; "
    : ''
  const imgSrc = watchMode
    ? "img-src 'self' data: https://i.ytimg.com; "
    : "img-src 'self' data:; "
  // font-src 'self' — шрифты самохостятся из /assets/fonts (routes/assets.ts);
  // внешние источники по-прежнему запрещены, CDN шрифтов не подключается.
  reply.header('Content-Security-Policy',
    `default-src 'none'; ${imgSrc}style-src 'unsafe-inline'; font-src 'self'; ${scriptSrc}${connectSrc}${frameSrc}base-uri 'none'; form-action 'none'`)
  reply.header('X-Content-Type-Options', 'nosniff')
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin')
  reply.header('X-Frame-Options', 'DENY')
  reply.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()')
}

function newNonce(): string {
  return crypto.randomBytes(16).toString('base64')
}

/// @font-face для самохостных шрифтов (routes/assets.ts отдаёт их из
/// backend/assets/fonts с иммутабельным кэшем).
///
/// Почему не Google Fonts: строгий CSP запрещает внешние источники, а сторонний
/// CDN — это ещё и лишний RTT и точка отказа. Сабсеты разнесены по unicode-range,
/// поэтому русская страница тянет только cyrillic+latin (~126 КБ), а latin-ext
/// не скачивается вовсе.
///
/// Дисплейный шрифт — Playfair Display, а не Instrument Serif из референсных
/// промтов: у Instrument Serif НЕТ кириллицы, а сайт русскоязычный.
function fontFaces(): string {
  const RANGES = {
    latin:
      'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,' +
      'U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD',
    'latin-ext':
      'U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,' +
      'U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF',
    cyrillic: 'U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116',
  } as const

  const face = (family: string, file: string, style: string, weights: string, subset: keyof typeof RANGES) =>
    `@font-face{font-family:'${family}';font-style:${style};font-weight:${weights};font-display:swap;` +
    `src:url(/assets/fonts/${file}-${subset}.woff2) format('woff2');unicode-range:${RANGES[subset]}}`

  return (Object.keys(RANGES) as (keyof typeof RANGES)[])
    .map((s) =>
      face('Playfair Display', 'playfair-italic', 'italic', '400 800', s) +
      face('Inter', 'inter', 'normal', '300 700', s))
    .join('\n  ')
}

// ── Переиспользуемые блоки установщика ─────────────────────────────────

/// Иконка приложения — рисуется кодом, чтобы не тянуть растровые ассеты.
function appIconSVG(size = 56): string {
  return `<svg width="${size}" height="${size}" viewBox="0 0 64 64" aria-hidden="true">
  <defs><linearGradient id="ai" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#15181a"/><stop offset="1" stop-color="#0a0c0d"/>
  </linearGradient></defs>
  <rect width="64" height="64" rx="15" fill="url(#ai)"/>
  <rect width="64" height="64" rx="15" fill="none" stroke="rgba(255,255,255,.22)" stroke-width="1"/>
  <polygon points="26 20 47 32 26 44" fill="#f2f4f3"/>
  <path d="M17 24v16" stroke="#f2f4f3" stroke-width="4" stroke-linecap="round" opacity=".9"/>
</svg>`
}

/// Блок «это приложение Plink»: иконка + имя + слоган.
function appIdentity(): string {
  return `<div class="app-id" data-reveal>
    ${appIconSVG(56)}
    <div><b>Plink</b><span>смотрим вместе · кадр в кадр</span></div>
  </div>`
}

/// Общий «хром» страницы: живой фон (aurora-орбы, луч, зерно, виньетка)
/// и стеклянный навбар.
function chrome(): string {
  return `<div class="bg" aria-hidden="true">
    <div class="orb o1"></div><div class="orb o2"></div><div class="orb o3"></div>
    <div class="beam"></div><div class="grain"></div><div class="vig"></div>
  </div>
  <div class="spot" aria-hidden="true"></div>
  <nav class="nav">
    <a class="nav-logo" href="/">${appIconSVG(26)}Plink</a>
    <div class="nav-links">
      <a href="/plus">Plink+</a>
      <a class="nav-cta" href="${escHTML(INSTALL_URL)}">Скачать</a>
    </div>
  </nav>`
}

/// Бегущая строка-кинотабло.
function marquee(): string {
  const line = 'Now Showing&ensp;·&ensp;Кадр в кадр&ensp;·&ensp;Смотрим вместе&ensp;·&ensp;3 · 2 · 1&ensp;·&ensp;'
  return `<div class="marquee" aria-hidden="true"><div>${line.repeat(4)}</div></div>`
}

/// Базовый скрипт всех страниц: scroll-reveal + 3D-tilt мокапа.
/// Пользовательские данные сюда не попадают.
function baseScript(nonce: string): string {
  return `<script nonce="${nonce}">
  (function () {
    var els = document.querySelectorAll('[data-reveal]');
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
        });
      }, { threshold: 0.12 });
      els.forEach(function (el) { io.observe(el); });
    } else {
      els.forEach(function (el) { el.classList.add('in'); });
    }
    var spot = document.querySelector('.spot');
    if (spot && matchMedia('(pointer:fine)').matches
        && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      addEventListener('mousemove', function (e) {
        spot.style.setProperty('--sx', e.clientX + 'px');
        spot.style.setProperty('--sy', e.clientY + 'px');
      }, { passive: true });
    }
    var wrap = document.querySelector('.phone-wrap');
    if (wrap && matchMedia('(pointer:fine)').matches
        && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      var phone = wrap.querySelector('.phone');
      wrap.addEventListener('mousemove', function (e) {
        var r = wrap.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width - 0.5;
        var y = (e.clientY - r.top) / r.height - 0.5;
        wrap.classList.add('tilting');
        // Дизайн-реф.: наклон <=12°, translateZ 24px, блик radial по --gx/--gy.
        phone.style.transform = 'translateZ(24px) rotateY(' + (x * 16).toFixed(2) + 'deg) rotateX(' + (-y * 12).toFixed(2) + 'deg)';
        phone.style.setProperty('--gx', ((x + 0.5) * 100).toFixed(1) + '%');
        phone.style.setProperty('--gy', ((y + 0.5) * 100).toFixed(1) + '%');
      });
      wrap.addEventListener('mouseleave', function () {
        wrap.classList.remove('tilting');
        phone.style.transform = '';
      });
    }
    // Гигантский фоновый текст (дизайн-реф.): scaleY тянется за высотой окна.
    var giant = document.querySelector('.giant');
    if (giant) {
      var fitGiant = function () {
        giant.style.setProperty('--gsy', Math.max(0.75, Math.min(1.7, innerHeight / 860)).toFixed(3));
      };
      fitGiant();
      addEventListener('resize', fitGiant, { passive: true });
    }
    // Магнитные кнопки (дизайн-реф.): CTA тянется к курсору в зоне ~48px
    // вокруг кнопки; отпускает той же транзишеной transform, что и hover.
    var magnets = document.querySelectorAll('a.btn, a.store-badge, a.nav-cta');
    if (magnets.length && matchMedia('(pointer:fine)').matches
        && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      var mRaf = 0;
      addEventListener('mousemove', function (e) {
        if (mRaf) return;
        mRaf = requestAnimationFrame(function () {
          mRaf = 0;
          magnets.forEach(function (m) {
            var r = m.getBoundingClientRect();
            // Расстояние до прямоугольника, не до центра: у широких кнопок
            // радиус от центра включал бы полэкрана по вертикали.
            var outX = Math.max(r.left - e.clientX, 0, e.clientX - r.right);
            var outY = Math.max(r.top - e.clientY, 0, e.clientY - r.bottom);
            if (outX < 48 && outY < 48) {
              var dx = e.clientX - (r.left + r.width / 2);
              var dy = e.clientY - (r.top + r.height / 2);
              m.style.setProperty('--mx', Math.max(-9, Math.min(9, dx * 0.22)).toFixed(1) + 'px');
              m.style.setProperty('--my', Math.max(-7, Math.min(7, dy * 0.22)).toFixed(1) + 'px');
            } else if (m.style.getPropertyValue('--mx') !== '') {
              m.style.removeProperty('--mx');
              m.style.removeProperty('--my');
            }
          });
        });
      }, { passive: true });
    }
  })();
  </script>`
}

/// Бейджи магазинов — двухстрочные, как настоящие кнопки установки.
function storeBadges(): string {
  const apple = `<a class="store-badge lg" href="${escHTML(INSTALL_URL)}">${icon('download', 22)}<span><small>${TESTFLIGHT_URL ? 'Тест в' : 'Загрузите в'}</small><b>${TESTFLIGHT_URL ? 'TestFlight' : 'App Store'}</b></span></a>`
  const android = ANDROID_STORE_URL
    ? `<a class="store-badge lg" href="${escHTML(ANDROID_STORE_URL)}">${icon('download', 22)}<span><small>Доступно в</small><b>Google Play</b></span></a>`
    : `<span class="store-badge lg disabled"><span><small>Скоро в</small><b>Google Play</b></span></span>`
  // data-reveal, иначе бейджи проявляются мгновенно между анимируемыми блоками.
  return `<div class="badges" data-reveal data-d="3">${apple}${android}</div>`
}

/// Мокап телефона с комнатой — как у Rave, но наш контент.
/// Всё содержимое проходит через escHTML.
function phoneMockup(roomName: string, mediaTitle: string | null, code: string, live = true): string {
  const badge = live
    ? '<span class="ps-live"><i></i>синхрон</span>'
    : '<span class="ps-live">завершён</span>'
  return `<div class="phone" aria-hidden="true">
    <div class="phone-screen">
      <div class="ps-top">${badge}<span class="ps-name">${escHTML(roomName)}</span></div>
      <div class="ps-video">
        <div class="ps-play">${icon('play', 22)}</div>
        ${mediaTitle ? `<div class="ps-media">${escHTML(mediaTitle)}</div>` : ''}
        <div class="ps-bar"><i></i></div>
      </div>
      <div class="ps-chat">
        <div class="ps-msg"><b>Хост</b>Запускаю — 3 · 2 · 1</div>
        <div class="ps-msg me">Жду!</div>
      </div>
      <div class="ps-code">КОД&nbsp;·&nbsp;${escHTML(code)}</div>
    </div>
  </div>`
}

// QR ведёт на канонический URL страницы: телефон откроет её же,
// а там — smart banner, диплинк и кнопки установки.
const qrCache = new Map<string, string>()
async function qrSVG(url: string): Promise<string> {
  const hit = qrCache.get(url)
  if (hit) return hit
  // Классический QR: тёмные модули на светлой подложке. Инвертированные
  // (светлое на прозрачном) читают не все камеры — старые iOS и часть Android.
  const svg = await QRCode.toString(url, {
    type: 'svg', margin: 0, errorCorrectionLevel: 'M',
    color: { dark: '#04201bff', light: '#eafaf7ff' },
  })
  if (qrCache.size > 200) qrCache.clear()
  qrCache.set(url, svg)
  return svg
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
      <stop offset="0%" stop-color="#070809"/>
      <stop offset="100%" stop-color="#101314"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <circle cx="1010" cy="140" r="210" fill="#eafaf7" opacity="0.10"/>
  <text x="80" y="270" font-family="-apple-system,Helvetica,Arial" font-size="64" font-weight="700" fill="#eafaf7">${escXML(title)}</text>
  <text x="80" y="340" font-family="-apple-system,Helvetica,Arial" font-size="32" fill="#8fb3ae">${escXML(subtitle)}</text>
  <text x="80" y="550" font-family="-apple-system,Helvetica,Arial" font-size="28" font-weight="600" fill="#eafaf7">Plink — смотрите вместе</text>
</svg>`
}

async function sendOG(reply: FastifyReply, title: string, subtitle: string) {
  const svg = ogSVG(title, subtitle)
  reply.header('Cache-Control', 'public, max-age=3600')
  try {
    // Sharp теперь в dependencies — OG отдаётся PNG
    // (мессенджеры не показывают SVG-превью). catch — на случай проблем
    // с нативным модулем в конкретной среде: тогда честный SVG-фолбэк.
    const { default: sharp } = await import('sharp')
    const png = await sharp(Buffer.from(svg)).png().toBuffer()
    return reply.type('image/png').send(png)
  } catch {
    return reply.type('image/svg+xml').send(svg)
  }
}

// Общая «шапка» страницы: мета, OG, smart app banner, базовые стили.
function pageHead(opts: {
  title: string
  description: string
  ogImage: string
  canonical: string
  deepLink?: string
}): string {
  const banner = opts.deepLink
    ? `app-id=${appStoreNumericID()}, app-argument=${escHTML(opts.deepLink)}`
    : `app-id=${appStoreNumericID()}`
  return `<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${escHTML(opts.title)}</title>
<link rel="canonical" href="${escHTML(opts.canonical)}">
<meta name="theme-color" content="#071214">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Plink">
<meta property="og:title" content="${escHTML(opts.title)}">
<meta property="og:description" content="${escHTML(opts.description)}">
<meta property="og:image" content="${escHTML(opts.ogImage)}">
<meta property="og:url" content="${escHTML(opts.canonical)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="${banner}">
<style>
  /* Plink v5 — кинематографичный яркий лендинг.
     Приёмы уровня референсов (liquid glass, серифный италик-дисплей,
     пословный blur-in, живой фон, spotlight) — без CDN: строгий CSP. */
  ${fontFaces()}
  :root {
    color-scheme: dark;
    /* --dim: 4.5:1 минимум на --black (#5d6a66 давал 3.6:1 при 10–12px) */
    --black:#050505; --ink:#f5f7f6; --mut:#a7b3af; --dim:#6f938c;
    --teal:#19e0c0; --violet:#7c5cff; --amber:#f5c26b;
    --serif:'Playfair Display','Didot','Bodoni 72',Georgia,'Times New Roman',serif;
    --sans:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
    --mono:ui-monospace,'SF Mono',Menlo,Consolas,monospace;
    --ease:cubic-bezier(.16,1,.3,1);
    /* совместимость со старыми токенами */
    --velvet:var(--black); --surface:#0d0f0f; --raised:#131616;
    --screen:var(--ink); --muted:var(--mut);
    --teal-soft:rgba(25,224,192,.35);
  }
  * { box-sizing:border-box }
  /* overflow-x:clip, а не hidden: clip не создаёт скролл-контейнер, поэтому
     мобильный Chrome/Safari не расширяет layout viewport под вылезший контент
     и position:sticky у потомков продолжает работать. */
  html { scroll-behavior:smooth; overflow-x:clip }
  body { margin:0; font:16px/1.55 var(--sans);
         background:var(--black); color:var(--ink); min-height:100vh;
         display:flex; flex-direction:column; align-items:center;
         padding:104px 20px calc(30px + env(safe-area-inset-bottom));
         overflow-x:clip; -webkit-font-smoothing:antialiased }

  /* ── Живой фон: цветная аврора + луч + зерно + виньетка ───────────── */
  .bg { position:fixed; inset:0; z-index:0; pointer-events:none; overflow:hidden }
  .bg .orb { position:absolute; border-radius:50%; filter:blur(90px); will-change:transform }
  .bg .o1 { width:64vmax; height:64vmax; left:-22vmax; top:-26vmax;
            background:radial-gradient(circle, rgba(25,224,192,.22), transparent 62%);
            animation:drift1 34s ease-in-out infinite alternate }
  .bg .o2 { width:56vmax; height:56vmax; right:-20vmax; top:2vmax;
            background:radial-gradient(circle, rgba(124,92,255,.20), transparent 62%);
            animation:drift2 44s ease-in-out infinite alternate; animation-delay:-12s }
  .bg .o3 { width:48vmax; height:48vmax; left:18vmax; bottom:-24vmax;
            background:radial-gradient(circle, rgba(245,194,107,.12), transparent 58%);
            animation:drift3 52s ease-in-out infinite alternate; animation-delay:-25s }
  @keyframes drift1 { 50%{transform:translate(7vmax,6vmax) scale(1.18) rotate(6deg)} 100%{transform:translate(-4vmax,3vmax) scale(1.05)} }
  @keyframes drift2 { 50%{transform:translate(-8vmax,8vmax) scale(1.1) rotate(-5deg)} 100%{transform:translate(3vmax,-5vmax) scale(.94)} }
  @keyframes drift3 { 50%{transform:translate(6vmax,-9vmax) scale(1.15)} 100%{transform:translate(-5vmax,4vmax) scale(1.02)} }
  .bg .beam { position:absolute; inset:0;
          background:conic-gradient(from 180deg at 50% -18%, transparent 42%,
            rgba(25,224,192,.10) 47.5%, rgba(245,247,246,.14) 50%,
            rgba(124,92,255,.10) 52.5%, transparent 58%);
          animation:flicker 9s ease-in-out infinite }
  @keyframes flicker { 0%,100%{opacity:.85} 42%{opacity:1} 47%{opacity:.65} 52%{opacity:.92} }
  .bg .grain { position:absolute; inset:-40%; opacity:.05; mix-blend-mode:overlay;
          background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='240' height='240'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%25' height='100%25' filter='url(%23n)' opacity='0.6'/></svg>");
          animation:grain 1.4s steps(4) infinite }
  @keyframes grain { 25%{transform:translate(-3%,2%)} 50%{transform:translate(2%,-3%)} 75%{transform:translate(-2%,-2%)} }
  .bg .vig { position:absolute; inset:0;
          background:radial-gradient(130% 100% at 50% 36%, transparent 50%, rgba(0,0,0,.62)) }
  /* Spotlight за курсором (desktop, JS двигает --sx/--sy) */
  .spot { position:fixed; inset:0; z-index:1; pointer-events:none; mix-blend-mode:screen;
          background:radial-gradient(300px circle at var(--sx,-30%) var(--sy,-30%),
            rgba(245,247,246,.09), rgba(25,224,192,.05) 45%, transparent 70%) }

  /* ── Liquid glass (по референсу, 2 веса) ──────────────────────────── */
  .lg, .lg-s { position:relative; overflow:hidden; background:rgba(255,255,255,.012);
        background-blend-mode:luminosity;
        backdrop-filter:blur(8px); -webkit-backdrop-filter:blur(8px);
        border:none; box-shadow:inset 0 1px 1px rgba(255,255,255,.10) }
  .lg::before, .lg-s::before { content:''; position:absolute; inset:0; border-radius:inherit;
        padding:1.4px; pointer-events:none;
        background:linear-gradient(180deg, rgba(255,255,255,.45) 0%, rgba(255,255,255,.15) 20%,
          rgba(255,255,255,0) 40%, rgba(255,255,255,0) 60%,
          rgba(255,255,255,.15) 80%, rgba(255,255,255,.45) 100%);
        -webkit-mask:linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
        -webkit-mask-composite:xor; mask-composite:exclude }
  .lg-s { backdrop-filter:blur(40px); -webkit-backdrop-filter:blur(40px);
        box-shadow:4px 4px 4px rgba(0,0,0,.05), inset 0 1px 1px rgba(255,255,255,.15) }
  .lg-s::before { background:linear-gradient(180deg, rgba(255,255,255,.5) 0%, rgba(255,255,255,.2) 20%,
          rgba(255,255,255,0) 40%, rgba(255,255,255,0) 60%,
          rgba(255,255,255,.2) 80%, rgba(255,255,255,.5) 100%) }

  /* ── Плавающий стеклянный навбар-капсула ──────────────────────────── */
  .nav { position:fixed; top:16px; left:50%; transform:translateX(-50%); z-index:60;
         display:flex; align-items:center; gap:4px; padding:7px 8px; border-radius:9999px;
         background:rgba(10,11,11,.42);
         backdrop-filter:blur(22px) saturate(1.4); -webkit-backdrop-filter:blur(22px) saturate(1.4);
         box-shadow:inset 0 1px 1px rgba(255,255,255,.12), 0 18px 46px -18px rgba(0,0,0,.85);
         max-width:calc(100vw - 24px) }
  .nav-logo { display:flex; align-items:center; gap:9px; text-decoration:none;
              color:var(--ink); font:italic 600 19px/1 var(--serif); letter-spacing:-.02em;
              padding:6px 12px 6px 6px }
  .nav-links { display:flex; align-items:center; gap:2px }
  .nav-links a { color:rgba(245,247,246,.85); text-decoration:none; font-size:14px; font-weight:500;
                 padding:9px 15px; border-radius:9999px; transition:color .2s, background .2s;
                 white-space:nowrap }
  .nav-links a:hover { color:#fff; background:rgba(255,255,255,.08) }
  .nav-links a.nav-cta { color:#0a0b0b; background:#fff; font-weight:700;
                 box-shadow:0 8px 24px -8px rgba(255,255,255,.35);
                 transform:translate3d(var(--mx,0px),var(--my,0px),0);
                 transition:color .2s, background .2s, transform .25s var(--ease) }
  .nav-links a.nav-cta:hover { background:#e9efed;
                 transform:translate3d(var(--mx,0px),var(--my,0px),0) translateY(-1px) }

  .card { position:relative; z-index:2; max-width:560px; width:100%;
          text-align:center; margin:auto; padding-top:22px }

  [data-reveal] { opacity:0; transform:translateY(24px); filter:blur(8px);
                  transition:opacity .8s var(--ease), transform .9s var(--ease), filter .8s var(--ease) }
  [data-reveal].in { opacity:1; transform:none; filter:none }
  [data-reveal][data-d="1"]{transition-delay:.08s} [data-reveal][data-d="2"]{transition-delay:.16s}
  [data-reveal][data-d="3"]{transition-delay:.24s} [data-reveal][data-d="4"]{transition-delay:.32s}

  /* Пословный blur-in для дисплей-заголовков */
  .bw { display:inline-block; max-width:100%; overflow-wrap:anywhere;
        margin-right:.24em; opacity:0; filter:blur(10px);
        transform:translateY(46px);
        animation:bw .8s var(--ease) forwards; animation-delay:var(--d,0s) }
  @keyframes bw { 55%{opacity:.55; filter:blur(4px); transform:translateY(-5px)}
                  100%{opacity:1; filter:blur(0); transform:translateY(0)} }
  @media (prefers-reduced-motion:reduce) {
    .bg .orb,.bg .beam,.bg .grain{animation:none}
    [data-reveal]{opacity:1;transform:none;filter:none;transition:none}
    .bw{animation:none;opacity:1;filter:none;transform:none}
    .spot{display:none}
  }

  .eyebrow { display:inline-flex; align-items:center; gap:10px; border-radius:9999px;
             padding:7px 16px 7px 8px; margin-bottom:26px; max-width:100%;
             font:600 13px/1 -apple-system,sans-serif; color:rgba(245,247,246,.92);
             /* здесь живёт имя хоста из БД */
             overflow-wrap:anywhere }
  .eyebrow::before,.eyebrow::after { content:none }
  .eyebrow .dot { width:auto; height:auto; border-radius:9999px; background:#fff; color:#0a0b0b;
                  box-shadow:none; animation:none; padding:5px 11px;
                  font:700 11px/1 -apple-system,sans-serif }
  .eyebrow .dot::after { content:'LIVE' }
  /* Завершённый сеанс: значок не должен кричать LIVE рядом с «Сеанс завершён». */
  /* Плашка непрозрачная: контраст #0a0b0b на #c9d1ce = 12.7:1 при 11px/700. */
  .eyebrow.ended .dot { background:#c9d1ce; color:#0a0b0b }
  .eyebrow.ended .dot::after { content:'ENDED' }

  h1, .display { font:italic 400 clamp(46px,9vw,96px)/0.95 var(--serif);
       letter-spacing:-.04em; margin:0 0 18px; color:var(--ink); font-weight:400;
       /* имя комнаты — до 120 символов, username — до 32: рвём неразрывное */
       overflow-wrap:anywhere }
  h1 .accent, .display .accent { background:linear-gradient(92deg,var(--teal),var(--violet));
       -webkit-background-clip:text; background-clip:text; color:transparent }
  h2 { font:italic 400 clamp(30px,5vw,52px)/1 var(--serif); letter-spacing:-.03em; margin:0 0 8px }
  .sec-sub { color:var(--mut); font-size:14.5px; margin:0 0 22px }
  p.sub { color:var(--mut); margin:0 auto 30px; max-width:46ch; font-size:16px; font-weight:300;
          line-height:1.5; overflow-wrap:anywhere }

  .meta { display:flex; justify-content:center; gap:8px; flex-wrap:wrap; margin:0 0 30px }
  .meta span { display:inline-flex; align-items:center; gap:7px; height:32px; padding:0 14px;
          border-radius:9999px; font:500 12px/1 -apple-system,sans-serif; color:rgba(245,247,246,.9);
          white-space:nowrap; max-width:100%; min-width:0 }
  /* Название видео приходит из БД и бывает длинным — обрезаем внутри чипа. */
  .meta b { min-width:0; overflow:hidden; text-overflow:ellipsis; font-weight:500 }
  .meta svg { color:var(--teal); flex:none }

  /* ── Билет: стеклянная карта с неоновым кодом ─────────────────────── */
  .ticket { position:relative; text-align:left; margin:0 0 26px; border-radius:22px }
  .ticket-top { padding:22px 26px 20px }
  .ticket-row { display:flex; justify-content:space-between; align-items:baseline; gap:12px }
  .ticket-label { font:700 10px/1 var(--mono); letter-spacing:.3em; color:var(--dim);
                  text-transform:uppercase }
  .stamp { font:800 10px/1 var(--mono); letter-spacing:.18em; color:var(--amber);
           border:1.5px solid rgba(245,194,107,.55); border-radius:7px;
           padding:5px 9px; transform:rotate(3deg) }
  .code { display:flex; gap:8px; margin-top:16px }
  .code span { flex:1; display:inline-flex; align-items:center; justify-content:center;
               height:60px; font:800 28px/1 var(--mono); color:var(--teal);
               background:rgba(0,0,0,.5); border:1px solid rgba(25,224,192,.28);
               border-radius:12px; text-shadow:0 0 20px rgba(25,224,192,.55) }
  .rip { position:relative; height:0; border-top:2px dashed rgba(245,247,246,.16) }
  .rip::before,.rip::after { content:''; position:absolute; top:-11px; width:22px; height:22px;
               border-radius:50%; background:var(--black) }
  .rip::before { left:-11px } .rip::after { right:-11px }
  .ticket-bottom { display:flex; justify-content:space-between; align-items:center;
                   padding:15px 26px 17px; gap:12px }
  .ticket-note { font:600 11px/1.5 var(--mono); letter-spacing:.05em; color:var(--dim) }
  button.copy { display:inline-flex; align-items:center; gap:8px; background:none; border:none;
                border-radius:9999px; color:var(--ink); font:600 13px/1 -apple-system,sans-serif;
                padding:11px 16px; cursor:pointer; transition:transform .2s }
  button.copy:hover { transform:translateY(-1px) }

  a.btn { position:relative; display:flex; align-items:center; justify-content:center; gap:10px;
          width:100%; color:#fff; text-decoration:none; border-radius:9999px;
          font-weight:600; font-size:16px; padding:17px 30px;
          transform:translate3d(var(--mx,0px),var(--my,0px),0);
          transition:transform .25s var(--ease), box-shadow .25s }
  a.btn:hover { transform:translate3d(var(--mx,0px),var(--my,0px),0) translateY(-2px) scale(1.01);
          box-shadow:0 24px 56px -18px rgba(25,224,192,.35) }
  a.btn:active { transform:translate3d(var(--mx,0px),var(--my,0px),0) scale(.99) }
  #install-hint { display:none; margin-top:16px; color:var(--amber); font-size:14px }
  #install-hint.show { display:block }

  .steps { margin:36px auto 0; max-width:560px; text-align:left; border-radius:20px; overflow:hidden }
  .steps > div { display:flex; align-items:baseline; gap:14px; padding:14px 20px }
  .steps > div + div { border-top:1px solid rgba(245,247,246,.07) }
  .steps b { font:800 12px/1 var(--mono); color:var(--teal); letter-spacing:.1em }
  .steps span { color:#c4d0cc; font-size:14.5px }
  .steps .mono { font-family:var(--mono); color:var(--teal) }

  /* Партнёрская строка — крупный италик-сериф как в референсе */
  .partners { display:flex; justify-content:center; align-items:baseline; gap:clamp(20px,5vw,56px);
              flex-wrap:wrap; margin-top:40px;
              font:italic 400 clamp(22px,3.4vw,34px)/1 var(--serif); letter-spacing:-.02em;
              color:rgba(245,247,246,.92) }

  /* margin-left:calc(50% - 50vw) — полноширинная лента из центрированного
     контейнера. Раньше width:100vw стартовал с padding-кромки .card (x=20),
     торчал на 20px вправо и раздувал мобильный layout viewport до 410px —
     весь лендинг на телефоне обрезался по правому краю. */
  .marquee { position:relative; z-index:2; width:100vw; margin:48px 0 0 calc(50% - 50vw);
             padding:13px 0; overflow:hidden; white-space:nowrap;
             border-top:1px solid rgba(245,247,246,.07);
             border-bottom:1px solid rgba(245,247,246,.07);
             mask-image:linear-gradient(90deg,transparent,#000 12%,#000 88%,transparent) }
  .marquee div { display:inline-block; animation:marquee 34s linear infinite;
             font:700 11px/1 var(--mono); letter-spacing:.34em; color:var(--dim);
             text-transform:uppercase }
  @keyframes marquee { to { transform:translateX(-50%) } }
  @media (prefers-reduced-motion:reduce){ .marquee div{animation:none} }

  /* ── Карточки-возможности (стекло, иконка + теги + сериф-титул) ───── */
  .filmstrip { margin:30px 0 0; padding:0; border:none; background:none }
  .frames { display:grid; grid-template-columns:1fr; gap:14px; text-align:left }
  .frame { border-radius:22px; padding:22px; min-height:250px; display:flex; flex-direction:column;
           transition:transform .3s var(--ease) }
  .frame:hover { transform:translateY(-4px) }
  .frame-top { display:flex; align-items:flex-start; justify-content:space-between; gap:12px }
  .frame .fi { display:inline-flex; padding:11px; border-radius:14px; color:#fff }
  .frame .tags { display:flex; flex-wrap:wrap; justify-content:flex-end; gap:6px; max-width:70% }
  .frame .tags i { font:500 11px/1 -apple-system,sans-serif; font-style:normal;
           color:rgba(245,247,246,.9); border-radius:9999px; padding:6px 11px; white-space:nowrap }
  .frame-spacer { flex:1; min-height:26px }
  .frame b { display:block; font:italic 400 clamp(26px,4vw,34px)/1 var(--serif);
           letter-spacing:-.02em; color:var(--ink) }
  .frame span.desc { color:var(--mut); font-size:14px; font-weight:300; line-height:1.45;
           margin-top:10px; max-width:34ch }
  /* Sticky-стек фич (дизайн-реф.): на узких экранах карточки складываются
     одна на другую при скролле. Глубину даёт backdrop-blur самих карточек,
     непрозрачная подложка — чтобы текст нижней не просвечивал сквозь верхнюю. */
  @media (max-width:899px) {
    .frames { --deck:14px }
    .frames .frame { position:sticky; top:calc(76px + var(--fi,0)*var(--deck));
                     background:rgba(13,17,18,.88) }
    .frames .frame:nth-child(1){--fi:0} .frames .frame:nth-child(2){--fi:1}
    .frames .frame:nth-child(3){--fi:2} .frames .frame:nth-child(4){--fi:3}
  }

  /* Гигантский фоновый текст (дизайн-реф.): призрак вордмарка за контентом,
     вертикаль тянется за innerHeight через --gsy (ставит baseScript). */
  .giant { position:fixed; left:50%; bottom:-.12em; z-index:1; pointer-events:none;
           user-select:none; white-space:nowrap;
           transform:translateX(-50%) scaleY(var(--gsy,1)); transform-origin:50% 100%;
           font:italic 700 clamp(150px,26vw,430px)/0.8 var(--serif); letter-spacing:-.05em;
           color:transparent; -webkit-text-stroke:1px rgba(234,250,247,.055);
           background:linear-gradient(180deg, rgba(234,250,247,.04), rgba(234,250,247,0) 80%);
           -webkit-background-clip:text; background-clip:text }

  .frame .tag { display:inline-block; margin-left:8px; font:700 9px/1 var(--mono);
                letter-spacing:.14em; color:var(--amber); border:1px solid rgba(245,194,107,.4);
                border-radius:5px; padding:3px 6px; vertical-align:6px }

  .foot-nav { display:flex; justify-content:center; gap:8px; flex-wrap:wrap; margin-top:34px }
  .foot-nav a { color:var(--mut); text-decoration:none; font-size:13.5px; font-weight:500;
                padding:10px 16px; border-radius:9999px; transition:color .2s, background .2s }
  .foot-nav a:hover { color:var(--ink); background:rgba(255,255,255,.06) }
  footer { margin-top:36px; font:600 10px/1.8 var(--mono); letter-spacing:.28em;
           text-transform:uppercase; color:var(--dim); text-align:center }
  :focus-visible { outline:2px solid var(--teal); outline-offset:3px; border-radius:8px }
  @media (max-width:390px){ .code span{height:54px;font-size:24px} }

  /* ── Установщик ───────────────────────────────────────────────────── */
  .app-id { display:flex; align-items:center; gap:14px; justify-content:center;
            margin-bottom:24px; text-align:left }
  .app-id svg { filter:drop-shadow(0 12px 30px rgba(25,224,192,.25)) }
  .app-id b { display:block; font:italic 500 24px/1 var(--serif); letter-spacing:-.02em }
  .app-id span { display:block; color:var(--mut); font-size:13px; margin-top:3px }
  .badges { display:flex; flex-wrap:wrap; gap:10px; justify-content:center; margin-top:14px }
  .badges > * { flex:1 1 210px; max-width:230px }
  .store-badge { display:flex; align-items:center; justify-content:center; gap:10px;
                 text-align:left; height:58px; border-radius:9999px;
                 text-decoration:none; color:var(--ink); padding:0 20px;
                 transform:translate3d(var(--mx,0px),var(--my,0px),0);
                 transition:transform .25s var(--ease) }
  .store-badge:hover { transform:translate3d(var(--mx,0px),var(--my,0px),0) translateY(-2px) }
  .store-badge small { display:block; font-size:10.5px; color:var(--mut) }
  .store-badge b { display:block; font-size:15.5px; font-weight:600; line-height:1.15 }
  .store-badge.disabled { opacity:.45; pointer-events:none }
  .hero-grid { display:grid; grid-template-columns:1fr; gap:36px; align-items:center;
               text-align:center }
  .qr-block { display:none; align-items:center; gap:14px; margin-top:24px;
              padding:14px 16px; border-radius:18px; text-align:left }
  /* Белая карточка-подложка + padding вместо quiet zone (margin:0 в qrSVG).
     Модуль при 86px — 2.97..3.44px (25..29 модулей), значит четыре модуля
     quiet zone по ISO/IEC 18004 — это >=13.8px. */
  .qr-block svg { width:86px; height:86px; flex:none; box-sizing:content-box;
              background:#eafaf7; padding:14px; border-radius:10px }
  .qr-block span { color:var(--mut); font-size:13.5px; line-height:1.45 }
  .qr-block b { color:var(--ink) }

  .phone-wrap { display:none; perspective:1100px }
  .phone { position:relative; width:256px; margin:0 auto; padding:12px; border-radius:40px;
           background:linear-gradient(160deg,#232827,#0b0d0d);
           border:1px solid rgba(245,247,246,.14);
           box-shadow:0 44px 100px -30px rgba(0,0,0,.95), 0 0 90px -24px rgba(25,224,192,.35),
                      0 0 90px -40px rgba(124,92,255,.3);
           transition:transform .35s var(--ease); will-change:transform;
           animation:float 7s ease-in-out infinite;
           /* Отражение под мокапом (дизайн-реф.). Градиент здесь — маска
              видимости: у корпуса 30% и к 45% высоты сходит в ноль. Работает
              в WebKit/Blink; Firefox просто не рисует отражение. */
           -webkit-box-reflect:below 24px linear-gradient(rgba(0,0,0,.3), transparent 45%) }
  /* Блик, следующий за курсором при тилте; --gx/--gy ставит baseScript. */
  .phone::after { content:''; position:absolute; inset:12px; border-radius:30px;
           background:radial-gradient(230px circle at var(--gx,50%) var(--gy,28%),
             rgba(234,250,247,.17), rgba(234,250,247,.05) 45%, transparent 70%);
           opacity:0; transition:opacity .35s var(--ease); pointer-events:none }
  @keyframes float { 50%{transform:translateY(-12px)} }
  .phone-wrap.tilting .phone { animation:none }
  .phone-wrap.tilting .phone::after { opacity:1 }
  @media (prefers-reduced-motion:reduce){ .phone{animation:none} }
  .phone-screen { --teal:#19e0c0; --amber:#f5c26b;
                  border-radius:30px; overflow:hidden; background:#071214;
                  border:1px solid rgba(245,247,246,.07) }
  .ps-top { display:flex; justify-content:space-between; align-items:center;
            padding:12px 14px 10px; border-bottom:1px solid rgba(245,247,246,.06) }
  .ps-live { display:inline-flex; align-items:center; gap:6px;
             font:700 9px/1 var(--mono); letter-spacing:.18em; text-transform:uppercase;
             color:var(--teal) }
  .ps-live i { width:5px; height:5px; border-radius:50%; background:var(--teal);
               box-shadow:0 0 8px var(--teal); animation:pulse 2s infinite }
  @keyframes pulse { 50%{opacity:.35} }
  .ps-name { font-size:11px; font-weight:700; color:#eafaf7;
             white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:120px }
  .ps-video { position:relative; aspect-ratio:16/10; display:flex; align-items:center;
              justify-content:center;
              background:radial-gradient(90% 100% at 30% 10%, #143036, #081215 60%),
                         radial-gradient(70% 80% at 80% 90%, rgba(124,92,255,.25), transparent) }
  .ps-play { display:flex; width:46px; height:46px; align-items:center; justify-content:center;
             border-radius:50%; color:#03201b; background:var(--teal);
             box-shadow:0 8px 28px rgba(25,224,192,.55) }
  .ps-media { position:absolute; left:10px; top:9px; font:600 9px/1 var(--mono);
              letter-spacing:.08em; color:#8fb3ae }
  .ps-bar { position:absolute; left:10px; right:10px; bottom:9px; height:3px;
            border-radius:3px; background:rgba(234,250,247,.14); overflow:hidden }
  .ps-bar i { display:block; width:62%; height:100%; background:var(--teal);
              box-shadow:0 0 8px var(--teal); animation:progress 9s ease-in-out infinite alternate }
  @keyframes progress { from{width:38%} to{width:74%} }
  .ps-chat { padding:10px 12px; display:flex; flex-direction:column; gap:6px }
  .ps-msg { align-self:flex-start; max-width:85%; font-size:11px; color:#cfe4df;
            background:rgba(234,250,247,.06); border:1px solid rgba(234,250,247,.07);
            padding:6px 10px; border-radius:11px 11px 11px 4px }
  .ps-msg b { color:var(--teal); margin-right:5px; font-family:-apple-system,sans-serif;
              font-style:normal; font-size:11px }
  .ps-msg.me { align-self:flex-end; background:rgba(25,224,192,.16);
               border-color:rgba(25,224,192,.22); color:#eafaf7;
               border-radius:11px 11px 4px 11px }
  .ps-code { padding:0 12px 12px; font:700 9px/1 var(--mono); letter-spacing:.22em;
             color:#5d6a66; text-align:center }

  @media (min-width:900px) {
    .card.wide { max-width:1080px; padding-top:40px }
    .hero-grid { grid-template-columns:1.12fr .88fr; text-align:left; gap:60px }
    .hero-grid h1, .hero-grid p.sub { margin-left:0 }
    .hero-grid .meta, .hero-grid .badges { justify-content:flex-start }
    .hero-grid .app-id { justify-content:flex-start }
    .qr-block { display:flex }
    .phone-wrap { display:block }
    .frames { grid-template-columns:repeat(2,1fr) }
    .frames .frame:first-child { grid-column:1 / -1 }
  }
  @media (min-width:1100px){ .frames { grid-template-columns:repeat(3,1fr) }
    .frames .frame:first-child { grid-column:auto } }

  /* ── /plus ────────────────────────────────────────────────────────── */
  .plans { display:grid; grid-template-columns:1fr; gap:14px; margin:32px 0 0; text-align:left }
  .plan { position:relative; padding:24px; border-radius:22px;
          transition:transform .3s var(--ease) }
  .plan:hover { transform:translateY(-4px) }
  .plan.hot::after { content:''; position:absolute; inset:0; border-radius:inherit;
          box-shadow:inset 0 0 0 1.5px rgba(245,194,107,.5); pointer-events:none }
  .plan .flag { position:absolute; top:-12px; right:18px; font:800 9.5px/1 var(--mono);
                letter-spacing:.14em; color:#14100a; background:var(--amber);
                border-radius:7px; padding:6px 10px; z-index:1 }
  .plan h3 { margin:0 0 3px; font:italic 400 24px/1 var(--serif); letter-spacing:-.02em }
  .plan .per { color:var(--dim); font:600 10.5px/1 var(--mono); letter-spacing:.08em }
  .plan .price { margin:16px 0 4px; font:italic 400 44px/1 var(--serif); letter-spacing:-.03em }
  .plan .price small { font-size:17px; color:var(--mut) }
  .plan .note { color:var(--mut); font-size:12.5px; min-height:34px; font-weight:300 }
  .plan button { width:100%; margin-top:14px; background:#fff; color:#0a0b0b;
                 font-weight:700; font-size:15px; border:none; border-radius:9999px;
                 padding:14px; cursor:pointer; transition:transform .2s var(--ease) }
  .plan button:hover { transform:translateY(-1px) }
  .plan button:disabled { opacity:.4; cursor:default; transform:none }
  .perks { margin:32px 0 0; text-align:left; display:grid; grid-template-columns:1fr 1fr; gap:9px 18px }
  .perks div { display:flex; gap:9px; align-items:baseline; color:#c4d0cc; font-size:14px;
               font-weight:300 }
  .perks svg { flex:none; color:var(--teal); transform:translateY(2px) }
  .checkout { display:none; margin:28px 0 0; padding:24px; text-align:left; border-radius:22px }
  .checkout.show { display:block }
  .checkout h3 { margin:0 0 4px; font:italic 400 22px/1 var(--serif) }
  .checkout .sel { color:var(--mut); font-size:13px; margin-bottom:16px }
  .checkout label { display:block; font:700 10px/1 var(--mono); letter-spacing:.2em;
                    text-transform:uppercase; color:var(--dim); margin:12px 0 6px }
  .checkout input { width:100%; background:rgba(0,0,0,.45); border:1px solid rgba(245,247,246,.14);
                    border-radius:14px; color:var(--ink); font-size:16px; padding:14px 16px;
                    transition:border-color .2s }
  .checkout input:focus { border-color:var(--teal-soft); outline:none }
  .checkout .pay { width:100%; margin-top:18px; display:flex; justify-content:center;
                   align-items:center; gap:9px; background:#fff; color:#0a0b0b;
                   font-weight:700; font-size:16px; border:none; border-radius:9999px;
                   padding:16px; cursor:pointer }
  .checkout .err { display:none; margin-top:12px; color:#ff9d80; font-size:13.5px }
  .checkout .err.show { display:block }
  .checkout .fine { margin-top:14px; color:var(--dim); font-size:12px; line-height:1.6 }
  @media (min-width:760px){ .plans{grid-template-columns:repeat(3,1fr)} .card.wide-p{max-width:880px} }
</style>`
}

// Простой лендинг (404-кейсы, профиль).
function landing(opts: {
  title: string
  heading: string
  subheading: string
  ogImage: string
  canonical: string
  nonce: string
}): string {
  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({ title: opts.title, description: opts.subheading, ogImage: opts.ogImage, canonical: opts.canonical })}
</head>
<body>
  ${chrome()}
  <div class="card">
    <div class="eyebrow lg" data-reveal><span class="dot"></span><span>Plink</span></div>
    <h1 class="display">${blurWords(opts.heading)}</h1>
    <p class="sub" data-reveal data-d="2">${escHTML(opts.subheading)}</p>
    <a class="btn lg-s" data-reveal data-d="3" href="${escHTML(INSTALL_URL)}">${icon('download')}Скачать Plink</a>
    <div class="foot-nav" data-reveal data-d="4">
      <a href="/">Что такое Plink?</a>
      <a href="/plus">Подписка Plink+</a>
    </div>
    <footer data-reveal data-d="4">Plink · смотрим вместе</footer>
  </div>
  ${baseScript(opts.nonce)}
</body>
</html>`
}

// Лендинг-установщик комнаты: приложение на первом плане (иконка, бейджи
// сторов, QR на десктопе, мокап телефона), билет с кодом, авто-открытие.
// Единственный источник данных для скрипта — код комнаты, прошедший
// ROOM_CODE_RE, вставленный через JSON.stringify.
async function installLanding(opts: {
  code: string
  roomName: string
  hostName: string | null
  mediaTitle: string | null
  participants: number
  isActive: boolean
  nonce: string
  /** When set, show install-free browser watch CTA (YouTube rooms). */
  watchPath?: string | null
}): Promise<string> {
  const deepLink = `plink://r/${opts.code}`
  const canonical = `${PUBLIC_ORIGIN}/r/${opts.code}`
  const title = `${opts.roomName} — Plink`
  const description = !opts.isActive
    ? 'Сеанс завершён. Создай свою комнату — кадр в кадр.'
    : opts.mediaTitle
      ? `Сейчас смотрят: ${opts.mediaTitle}. Присоединяйся — кадр в кадр.`
      : 'Присоединяйся к просмотру — кадр в кадр.'
  // Для завершённой комнаты нельзя рисовать «СЕАНС ИДЁТ»
  // и счётчик зала — комната уже неактивна.
  const inviteLine = !opts.isActive
    ? 'Сеанс завершён'
    : opts.hostName
      ? `${opts.hostName} зовёт на сеанс`
      : 'Тебя зовут на сеанс'
  const codeBoxes = opts.code.split('').map((c) => `<span>${escHTML(c)}</span>`).join('')
  const metaWatching = opts.mediaTitle
    ? `<span class="lg">${icon('play', 14)}<b>${escHTML(opts.mediaTitle)}</b></span>`
    : ''
  const metaPeople = !opts.isActive
    ? ''
    : opts.participants > 1
      ? `<span class="lg">${icon('users', 14)}в зале: ${opts.participants}</span>`
      : `<span class="lg">${icon('users', 14)}место свободно</span>`
  // Ревью аудита: у завершённой комнаты код бесполезен — вход по коду в API
  // требует isActive:true (rooms.ts), поэтому билет, копирование кода и шаг
  // «введи код» не показываем совсем, чтобы страница не противоречила себе.
  const ticket = !opts.isActive
    ? ''
    : `<div class="ticket lg" role="group" data-reveal data-d="2" aria-label="Билет: код комнаты ${escHTML(opts.code)}">
          <div class="ticket-top">
            <div class="ticket-row">
              <div class="ticket-label">Код комнаты</div>
              <div class="stamp">ADMIT&nbsp;+1</div>
            </div>
            <div class="code">${codeBoxes}</div>
          </div>
          <div class="rip"></div>
          <div class="ticket-bottom">
            <div class="ticket-note">PLINK&nbsp;CINEMA<br>СЕАНС&nbsp;ИДЁТ</div>
            <button class="copy lg" id="copy" type="button">${icon('copy', 15)}<span id="copy-text">Скопировать код</span></button>
          </div>
        </div>`
  const steps = !opts.isActive
    ? `<div><b>01</b><span>Установи Plink и войди</span></div>
      <div><b>02</b><span>Нажми «Создать комнату»</span></div>
      <div><b>03</b><span>Отправь ссылку друзьям — и вы смотрите вместе</span></div>`
    : `<div><b>01</b><span>Установи Plink и войди</span></div>
      <div><b>02</b><span>Нажми «Войти по коду»</span></div>
      <div><b>03</b><span>Введи <span class="mono">${escHTML(opts.code)}</span> — и вы смотрите вместе</span></div>`
  const ctaLink = opts.isActive ? deepLink : 'plink://'
  const ctaLabel = opts.isActive ? 'Открыть в Plink' : 'Создать свою комнату'
  const qr = await qrSVG(canonical)

  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({ title, description, ogImage: `${PUBLIC_ORIGIN}/og/r/${opts.code}.png`, canonical, deepLink: ctaLink })}
</head>
<body>
  ${chrome()}
  <div class="card wide">
    <div class="hero-grid">
      <div>
        ${appIdentity()}
        <div class="eyebrow lg${opts.isActive ? '' : ' ended'}" data-reveal><span class="dot"></span><span>${escHTML(inviteLine)}</span></div>
        <h1 class="display">${blurWords(opts.roomName)}</h1>
        <div class="meta-wrap" style="display:contents"><div class="meta" data-reveal data-d="1">${metaWatching}${metaPeople}<span class="lg">${icon('timer', 14)}кадр в кадр</span></div></div>

        ${ticket}

        <a class="btn lg-s" data-reveal data-d="3" id="open" href="${escHTML(ctaLink)}">${icon('play')}${ctaLabel}</a>
        ${opts.isActive && opts.watchPath
          ? `<a class="btn lg-s" data-reveal data-d="3" href="${escHTML(opts.watchPath)}" style="margin-top:10px;background:transparent;border:1px solid rgba(255,255,255,.22)">${icon('play')}Смотреть в браузере</a>`
          : ''}
        <!-- Пусто намеренно: текст пишет скрипт уже после снятия display:none,
             иначе мутации live-региона не происходит и скринридер молчит. -->
        <div id="install-hint" role="status" aria-live="polite"></div>
        ${storeBadges()}

        <div class="qr-block lg" data-reveal data-d="4">
          ${qr}
          <span><b>С телефона?</b> Наведи камеру на QR —<br>откроется эта комната.</span>
        </div>
      </div>

      <div class="phone-wrap" data-reveal data-d="3">
        ${phoneMockup(opts.roomName, opts.mediaTitle, opts.code, opts.isActive)}
      </div>
    </div>

    ${marquee()}

    <div class="steps lg" data-reveal data-d="1">
      ${steps}
    </div>

    <div class="foot-nav" data-reveal data-d="2">
      <a href="/">Что такое Plink?</a>
      <a href="/plus">Подписка Plink+</a>
    </div>
    <footer data-reveal data-d="2">Plink · смотрим вместе · кадр в кадр</footer>
  </div>
  ${baseScript(opts.nonce)}
  <script nonce="${opts.nonce}">
  (function () {
    var code = ${JSON.stringify(opts.code)};
    var active = ${JSON.stringify(opts.isActive)};
    var hintText = ${JSON.stringify(opts.isActive
      ? 'Plink ещё не установлен — скачай и вернись по этой же ссылке.'
      : 'Plink ещё не установлен — скачай приложение и создай свою комнату.')};
    var deep = 'plink://r/' + code;
    var copyBtn = document.getElementById('copy');
    var copyText = document.getElementById('copy-text');
    if (copyBtn && copyText) copyBtn.addEventListener('click', function () {
      var write = (navigator.clipboard && navigator.clipboard.writeText)
        ? navigator.clipboard.writeText(code) : Promise.reject();
      write.then(function () {
        copyText.textContent = 'Скопировано';
        setTimeout(function () { copyText.textContent = 'Скопировать код'; }, 2000);
      }).catch(function () {});
    });
    function showHint() {
      if (document.hidden) return; // приложение открылось — подсказка не нужна
      var el = document.getElementById('install-hint');
      if (!el || el.classList.contains('show')) return;
      // Сначала показываем узел, потом пишем текст: мутация live-региона
      // должна происходить, когда он уже в дереве доступности.
      el.classList.add('show');
      el.textContent = hintText;
    }
    var openBtn = document.getElementById('open');
    if (openBtn) openBtn.addEventListener('click', function () {
      setTimeout(showHint, 1800);
    });
    // Как у Rave: на мобильном пробуем открыть приложение сразу.
    // Для завершённой комнаты автопереход не делаем — войти по коду нельзя.
    if (active && /iPhone|iPad|iPod|Android/i.test(navigator.userAgent)) {
      setTimeout(function () { window.location.href = deep; }, 500);
      setTimeout(showHint, 2300);
    }
  })();
  </script>
</body>
</html>`
}

// ── /plus: подписка Plink+ на сайте ────────────────────────────────────
// Оплата через ЮKassa; грант пишет те же поля, что покупка в приложении,
// поэтому подписка появляется в приложении сама (см. webpay.ts).
function plusLanding(nonce: string): string {
  const enabled = webPayConfigured()
  const months: Record<string, number> = { '1m': 1, '3m': 3, '12m': 12 }
  const fmt = (p: string) => String(Math.round(parseFloat(p)))
  const perMonth = (id: string, p: string) => Math.round(parseFloat(p) / months[id])

  const cards = (Object.entries(WEB_PLANS) as Array<[string, { title: string; days: number; price: string }]>)
    .map(([id, p]) => {
      const hot = id === '12m'
      const per = months[id] > 1 ? `≈ ${perMonth(id, p.price)} ₽ в месяц` : 'Гибко: месяц за месяцем'
      const label = id === '1m' ? 'Месяц' : id === '3m' ? '3 месяца' : 'Год'
      return `<div class="plan lg${hot ? ' hot' : ''}">
        ${hot ? '<div class="flag">САМЫЙ ВЫГОДНЫЙ</div>' : ''}
        <h3>${label}</h3>
        <div class="per">PLINK+ · ${p.days} ДНЕЙ</div>
        <div class="price">${fmt(p.price)} <small>₽</small></div>
        <div class="note">${per}</div>
        <button type="button" data-plan="${id}" ${enabled ? '' : 'disabled'}>Оформить</button>
      </div>`
    }).join('')

  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({
    title: 'Plink+ — подписка',
    description: 'Живые темы, кино-рамки сообщений, ИИ без лимитов и комнаты до 50 человек. Оформите на сайте — подписка появится в приложении автоматически.',
    ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
    canonical: `${PUBLIC_ORIGIN}/plus`,
  })}
</head>
<body>
  ${chrome()}
  <div class="card wide-p">
    <div class="eyebrow lg" data-reveal><span class="dot"></span><span>Plink+</span></div>
    <h1 class="display">${blurWords('Смотрите')}<span class="accent">${blurWords('шире.', 1)}</span></h1>
    <p class="sub" data-reveal data-d="2">Подписка привязана к аккаунту Plink: оформите здесь —
    и при следующем запуске приложение включит Plink+ само.</p>

    ${enabled ? '' : `<div id="install-hint" class="show" style="margin-bottom:6px">
      Оплата картой на сайте подключается. Пока Plink+ можно оформить в приложении.
    </div>`}

    <div class="plans" data-reveal data-d="2">${cards}</div>

    <div class="perks" data-reveal data-d="3">
      <div>${icon('layers', 15)}Живые темы комнат</div>
      <div>${icon('chat', 15)}Кино-рамки сообщений</div>
      <div>${icon('spark', 15)}ИИ без дневного лимита</div>
      <div>${icon('users', 15)}Комнаты до 50 человек</div>
      <div>${icon('timer', 15)}Приоритет в очереди ИИ</div>
      <div>${icon('play', 15)}Эмодзи-паки Plink+</div>
    </div>

    <div class="checkout lg" id="checkout">
      <h3>Вход в аккаунт Plink</h3>
      <div class="sel" id="sel-plan"></div>
      <form id="pay-form">
        <label for="pay-email">Email</label>
        <input id="pay-email" type="email" autocomplete="email" required placeholder="you@example.com">
        <label for="pay-pass">Пароль</label>
        <input id="pay-pass" type="password" autocomplete="current-password" required placeholder="Пароль от Plink">
        <button class="pay" type="submit">${icon('play', 16)}Перейти к оплате</button>
      </form>
      <div class="err" id="pay-err" role="alert" aria-live="assertive"></div>
      <div class="fine">Оплата через ЮKassa. Разовый платёж на выбранный срок, автосписаний нет —
      продление вручную. Подписка появится в приложении автоматически.</div>
    </div>

    <div class="foot-nav" data-reveal data-d="2">
      <a href="/terms">Условия использования</a>
      <a href="/privacy">Конфиденциальность</a>
      <a href="/support">Поддержка</a>
      <a href="/">Что такое Plink?</a>
    </div>
    <footer data-reveal data-d="2">Plink+ · один аккаунт — сайт и приложение</footer>
  </div>
  ${baseScript(nonce)}
  <script nonce="${nonce}">
  (function () {
    var plan = null;
    var names = { '1m': 'Месяц · ', '3m': '3 месяца · ', '12m': 'Год · ' };
    var prices = ${JSON.stringify(Object.fromEntries(Object.entries(WEB_PLANS).map(([k, v]) => [k, v.price])))};
    var box = document.getElementById('checkout');
    var sel = document.getElementById('sel-plan');
    var err = document.getElementById('pay-err');
    // Порядок важен: текст пишем только после показа узла (у .err display:none),
    // а при скрытии чистим — иначе повторная та же ошибка не даст мутации
    // live-региона и скринридер её не объявит.
    function hideErr() { err.classList.remove('show'); err.textContent = ''; }
    function showErr(msg) { err.classList.add('show'); err.textContent = msg; }
    document.querySelectorAll('.plan button[data-plan]').forEach(function (b) {
      b.addEventListener('click', function () {
        plan = b.getAttribute('data-plan');
        sel.textContent = 'Тариф: ' + names[plan] + Math.round(parseFloat(prices[plan])) + ' ₽';
        box.classList.add('show');
        hideErr();
        box.scrollIntoView({ behavior: 'smooth', block: 'center' });
      });
    });
    var form = document.getElementById('pay-form');
    if (form) form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (!plan) return;
      hideErr();
      var btn = form.querySelector('.pay');
      btn.disabled = true;
      fetch('/api/webpay/create', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: document.getElementById('pay-email').value.trim(),
          password: document.getElementById('pay-pass').value,
          plan: plan,
        }),
      }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
        .then(function (res) {
          if (res.ok && res.j.confirmationUrl) { window.location.href = res.j.confirmationUrl; return; }
          showErr((res.j && res.j.error) || 'Не получилось создать платёж. Попробуйте ещё раз.');
          btn.disabled = false;
        })
        .catch(function () {
          showErr('Сеть недоступна. Попробуйте ещё раз.');
          btn.disabled = false;
        });
    });
  })();
  </script>
</body>
</html>`
}

function plusSuccessLanding(nonce: string): string {
  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({
    title: 'Plink+ — оплата принята',
    description: 'Подписка появится в приложении автоматически.',
    ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
    canonical: `${PUBLIC_ORIGIN}/plus/success`,
  })}
</head>
<body>
  ${chrome()}
  <div class="card">
    <div class="eyebrow lg" data-reveal><span class="dot"></span><span>Plink+</span></div>
    <h1 class="display">${blurWords('Оплата принята')}</h1>
    <p class="sub" data-reveal data-d="2">Как только банк подтвердит платёж (обычно меньше минуты),
    подписка привяжется к аккаунту. Откройте Plink — приложение включит Plink+ само.</p>
    <a class="btn lg-s" data-reveal data-d="3" href="plink://">${icon('play')}Открыть Plink</a>
    <div class="foot-nav" data-reveal data-d="4">
      <a href="/plus">Вернуться к тарифам</a>
      <a href="/">Что такое Plink?</a>
    </div>
    <footer data-reveal data-d="4">Plink+ · один аккаунт — сайт и приложение</footer>
  </div>
  ${baseScript(nonce)}
</body>
</html>`
}

// Общие стили юридических и справочных страниц: длинный текст, выключка влево.
// Остальная страница — тот же хром и та же «шапка», что у лендингов.
function proseStyles(): string {
  return `<style>
  .card.prose { max-width:760px; text-align:left }
  .card.prose h1 { font-size:clamp(32px,5.5vw,54px); text-align:left; margin:0 0 12px }
  .card.prose .upd { color:var(--dim); font:600 10px/1.8 var(--mono); letter-spacing:.22em;
        text-transform:uppercase; margin:0 0 34px }
  .card.prose section { margin:0 0 26px }
  .card.prose h2 { font:600 15.5px/1.5 var(--sans); color:var(--ink); margin:0 0 8px }
  .card.prose p { color:var(--mut); font-size:15px; font-weight:300; line-height:1.62;
        margin:0; max-width:70ch }
  .card.prose a.mail { color:var(--teal); text-decoration:none;
        border-bottom:1px solid rgba(25,224,192,.38) }
  .card.prose a.mail:hover { border-bottom-color:var(--teal) }
  .card.prose .foot-nav { justify-content:flex-start }
  .card.prose footer { text-align:left }
</style>`
}

/// Юридическая страница. Текст приходит из ../web/legal.ts — это канонический
/// источник, и в приложении на него ведут ссылки из пейвола и настроек.
/// Пользовательских данных на странице нет вовсе, но escHTML всё равно стоит:
/// правка текста не должна становиться правкой разметки.
function legalLanding(nonce: string, doc: LegalDocument): string {
  const sections = doc.sections
    .map((s, i) => {
      const mail = s.email
        ? ` <a class="mail" href="mailto:${escHTML(s.email)}">${escHTML(s.email)}</a>`
        : ''
      return `    <section data-reveal data-d="2">
      <h2>${i + 1}. ${escHTML(s.heading)}</h2>
      <p>${escHTML(s.body)}${mail}</p>
    </section>`
    })
    .join('\n')

  const other = doc.slug === 'terms'
    ? { href: '/privacy', label: 'Конфиденциальность' }
    : { href: '/terms', label: 'Условия использования' }

  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({
    title: doc.title,
    description: doc.description,
    ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
    canonical: `${PUBLIC_ORIGIN}/${doc.slug}`,
  })}
${proseStyles()}
</head>
<body>
  ${chrome()}
  <div class="card prose">
    <h1 data-reveal>${escHTML(doc.heading)}</h1>
    <p class="upd" data-reveal data-d="1">Последнее обновление: ${escHTML(doc.updated)}</p>
${sections}
    <div class="foot-nav" data-reveal data-d="3">
      <a href="${other.href}">${other.label}</a>
      <a href="/support">Поддержка</a>
      <a href="/">Что такое Plink?</a>
    </div>
    <footer data-reveal data-d="3">Plink · смотрим вместе</footer>
  </div>
  ${baseScript(nonce)}
</body>
</html>`
}

/// Страница поддержки: адрес для App Store Connect (Support URL) и ответы на
/// то, с чем в приложении обращаются чаще всего. Каждый пункт описывает
/// поведение, которое в приложении действительно есть.
function supportLanding(nonce: string): string {
  const items: Array<{ q: string; a: string }> = [
    {
      q: 'Ссылка на комнату не открылась',
      a:
        'Попросите отправителя продиктовать код комнаты и введите его в приложении на экране ' +
        '«Присоединиться». Код работает всегда, даже если ссылка не открывается на вашем ' +
        'устройстве.',
    },
    {
      q: 'Видео не синхронизируется',
      a:
        'Plink показывает расхождение с ведущим прямо в комнате. Если оно растёт: проверьте сеть, ' +
        'затем попросите ведущего поставить паузу и снять её — все участники встанут на один кадр. ' +
        'Для сервисов по подписке синхронного плеера нет, там работает режим «смотрим рядом».',
    },
    {
      q: 'Подписка Plink+',
      a:
        'Купленная в приложении подписка управляется в настройках Apple ID: там же её можно ' +
        'отменить или восстановить. Купленная на сайте — разовый платёж на выбранный срок, ' +
        'автосписаний нет, продление вручную. Если Plink+ не включился, откройте приложение ' +
        'заново: статус подписки проверяется при запуске.',
    },
    {
      q: 'Удалить аккаунт',
      a:
        'В приложении: «Профиль» → «Удалить аккаунт». Заявка уходит на сервер, и у вас есть ' +
        '14 дней, чтобы её отменить, войдя снова. После этого данные аккаунта удаляются или ' +
        'анонимизируются.',
    },
  ]

  const sections = items
    .map(
      (it, i) => `    <section data-reveal data-d="2">
      <h2>${i + 1}. ${escHTML(it.q)}</h2>
      <p>${escHTML(it.a)}</p>
    </section>`,
    )
    .join('\n')

  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({
    title: 'Поддержка — Plink',
    description: 'Помощь по Plink: комнаты, синхронизация, подписка Plink+, удаление аккаунта.',
    ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
    canonical: `${PUBLIC_ORIGIN}/support`,
  })}
${proseStyles()}
</head>
<body>
  ${chrome()}
  <div class="card prose">
    <h1 data-reveal>Поддержка</h1>
    <p class="upd" data-reveal data-d="1">Plink · смотрим вместе</p>
${sections}
    <section data-reveal data-d="2">
      <h2>${items.length + 1}. Написать нам</h2>
      <p>Если ответа здесь нет — напишите, и опишите, что происходит и на каком устройстве:
      <a class="mail" href="mailto:${escHTML(SUPPORT_EMAIL)}?subject=Plink%20Support">${escHTML(SUPPORT_EMAIL)}</a></p>
    </section>
    <div class="foot-nav" data-reveal data-d="3">
      <a href="/terms">Условия использования</a>
      <a href="/privacy">Конфиденциальность</a>
      <a href="/">Что такое Plink?</a>
    </div>
    <footer data-reveal data-d="3">Plink · смотрим вместе</footer>
  </div>
  ${baseScript(nonce)}
</body>
</html>`
}

// Корневая страница «Что такое Plink» — сюда ведут все лендинги.
function homeLanding(nonce: string): string {
  return `<!doctype html>
<html lang="ru">
<head>
${pageHead({
    title: 'Plink — смотрим вместе, кадр в кадр',
    description: 'Совместный просмотр YouTube, VK Видео и Rutube с точной синхронизацией, чатом, реакциями и ИИ-компаньоном.',
    ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
    canonical: PUBLIC_ORIGIN,
  })}
</head>
<body>
  ${chrome()}
  <div class="giant" aria-hidden="true">Plink</div>
  <div class="card wide">
    <div class="hero-grid">
      <div>
        ${appIdentity()}
        <div class="eyebrow lg" data-reveal><span class="dot"></span><span>Now&nbsp;Showing</span></div>
        <h1 class="display">${blurWords('Смотрим вместе.')}<br><span class="accent">${blurWords('Кадр в кадр.', 3)}</span></h1>
        <p class="sub" data-reveal data-d="2">Plink держит видео синхронным у всех в комнате: play,
        пауза и перемотка происходят одновременно. Комната стартует с отсчёта
        3&nbsp;·&nbsp;2&nbsp;·&nbsp;1 — как сеанс в кино.</p>
        ${storeBadges()}
      </div>
      <div class="phone-wrap" data-reveal data-d="3">
        ${phoneMockup('Вечер с друзьями', 'Сейчас смотрят вместе', 'PLINK1')}
      </div>
    </div>

    ${marquee()}

    <div class="filmstrip" data-reveal data-d="1">
      <div class="frames">
        <div class="frame lg"><div class="frame-top"><span class="fi lg">${icon('timer', 22)}</span><span class="tags"><i class="lg">Отсчёт 3·2·1</i><i class="lg">Кадр в кадр</i><i class="lg">Сервер-время</i></span></div><div class="frame-spacer"></div><b>Синхронный сеанс</b><span class="desc">Один источник истины на комнату — никто не убегает вперёд и не отстаёт</span></div>
        <div class="frame lg"><div class="frame-top"><span class="fi lg">${icon('chat', 22)}</span><span class="tags"><i class="lg">Реакции поверх видео</i><i class="lg">Danmaku</i><i class="lg">Фото</i></span></div><div class="frame-spacer"></div><b>Чат и реакции</b><span class="desc">Обсуждайте не отрываясь от экрана — эмоции летят прямо по кадру</span></div>
        <div class="frame lg"><div class="frame-top"><span class="fi lg">${icon('spark', 22)}</span><span class="tags"><i class="lg">Подбор фильма</i><i class="lg">Вопросы по сюжету</i></span></div><div class="frame-spacer"></div><b>ИИ-компаньон</b><span class="desc">Подберёт что посмотреть и ответит на вопросы по фильму</span></div>
        <div class="frame lg"><div class="frame-top"><span class="fi lg">${icon('layers', 22)}</span><span class="tags"><i class="lg">Aurora</i><i class="lg">Cosmos</i><i class="lg">Magma</i><i class="lg">Verdant</i></span></div><div class="frame-spacer"></div><b>Живые темы<span class="tag">PLINK+</span></b><span class="desc">Комната подстраивается под настроение фильма</span></div>
      </div>
    </div>

    <div class="steps lg" data-reveal data-d="1" style="margin-top:38px">
      <div><b>01</b><span>Создай комнату и вставь ссылку на видео</span></div>
      <div><b>02</b><span>Отправь друзьям код или билет-ссылку</span></div>
      <div><b>03</b><span>Отсчёт 3&nbsp;·&nbsp;2&nbsp;·&nbsp;1 — и все смотрят один кадр</span></div>
    </div>

    <div class="partners" data-reveal data-d="2">
      <span>YouTube</span><span>VK Видео</span><span>Rutube</span>
    </div>

    <div class="foot-nav" data-reveal data-d="2">
      <a href="/plus">Подписка Plink+</a>
      <a href="/support">Поддержка</a>
      <a href="/terms">Условия использования</a>
      <a href="/privacy">Конфиденциальность</a>
    </div>
    <footer data-reveal data-d="2">Plink · смотрим вместе · Россия и СНГ</footer>
  </div>
  ${baseScript(nonce)}
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
              { '/': '/join/*', comment: 'Легаси-ссылки из старых share-текстов' },
            ],
          },
        ],
      },
      webcredentials: { apps: [`${APPLE_TEAM_ID}.${APPLE_BUNDLE_ID}`] },
    }
  })

  // —— Корневая страница «Что такое Plink» ——
  fastify.get('/', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    reply.header('Cache-Control', 'no-store')
    return reply.type('text/html; charset=utf-8').send(homeLanding(nonce))
  })

  // —— Легаси-ссылки из старых share-текстов ——
  fastify.get<{ Params: { code: string } }>('/join/:code', async (req, reply) => {
    const code = String(req.params.code ?? '').toUpperCase()
    return reply.redirect(`/r/${encodeURIComponent(code)}`, 302)
  })

  // —— Лендинг-установщик комнаты ——
  fastify.get<{ Params: { code: string } }>('/r/:code', async (req, reply) => {
    const code = String(req.params.code ?? '').toUpperCase()

    if (!ROOM_CODE_RE.test(code)) {
      const nonce404 = newNonce()
      securityHeaders(reply, nonce404)
      reply.header('Cache-Control', 'no-store')
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce: nonce404,
        title: 'Plink — комната не найдена',
        heading: 'Комната не найдена',
        subheading: 'Ссылка устарела или введена с ошибкой.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/r/${encodeURIComponent(code)}`,
      }))
    }

    const room = await prisma.room.findFirst({
      where: { code, hidden: false },
      // mediaTitle принадлежит WatchHistory, а не Room.
      select: {
        name: true,
        mediaItem: true,
        hostName: true,
        isActive: true,
        _count: { select: { participants: true } },
      },
    })

    if (!room) {
      const nonce404 = newNonce()
      securityHeaders(reply, nonce404)
      reply.header('Cache-Control', 'no-store')
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce: nonce404,
        title: 'Plink — комната закрыта',
        heading: 'Комната закрыта',
        subheading: 'Но вы можете создать свою за пару секунд.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/r/${code}`,
      }))
    }

    const nonce = newNonce()
    securityHeaders(reply, nonce)
    // Без явного Cache-Control прокси кэшировали страницу
    // эвристически и замораживали счётчик зала и название комнаты.
    reply.header('Cache-Control', 'no-store')
    const watchTarget = webWatchTargetFromMediaItem(room.mediaItem)
    const mediaTitle = mediaTitleFromMediaItem(room.mediaItem)
    return reply.type('text/html; charset=utf-8').send(await installLanding({
      code,
      roomName: room.name || 'Комната Plink',
      hostName: room.hostName || null,
      mediaTitle,
      participants: room._count?.participants ?? 0,
      isActive: room.isActive,
      nonce,
      watchPath: room.isActive && watchTarget ? `/w/${encodeURIComponent(code)}` : null,
    }))
  })

  // —— Install-free YouTube watch (guest JWT + sync.v2 follower) ——
  fastify.get<{ Params: { code: string } }>('/w/:code', async (req, reply) => {
    const code = String(req.params.code ?? '').toUpperCase()
    if (!ROOM_CODE_RE.test(code)) {
      const nonce404 = newNonce()
      securityHeaders(reply, nonce404)
      reply.header('Cache-Control', 'no-store')
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce: nonce404,
        title: 'Plink — комната не найдена',
        heading: 'Комната не найдена',
        subheading: 'Ссылка устарела или введена с ошибкой.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/w/${encodeURIComponent(code)}`,
      }))
    }

    const room = await prisma.room.findFirst({
      where: { code, hidden: false },
      select: {
        name: true,
        mediaItem: true,
        isActive: true,
      },
    })

    const nonce = newNonce()
    reply.header('Cache-Control', 'no-store')

    if (!room || !room.isActive) {
      securityHeaders(reply, nonce)
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce,
        title: 'Plink — комната закрыта',
        heading: 'Комната закрыта',
        subheading: 'Сеанс уже закончился. Создай свою комнату в приложении.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/w/${code}`,
      }))
    }

    const target = webWatchTargetFromMediaItem(room.mediaItem)
    if (!target) {
      securityHeaders(reply, nonce)
      return reply.type('text/html; charset=utf-8').send(webWatchUnsupportedHTML({
        code,
        roomName: room.name || 'Комната Plink',
        reason: 'В этой комнате кинотеатр или страница хоста. YouTube, VK и Rutube открываются в браузере; кинотеатры — в приложении Plink («ваш экран»).',
        nonce,
        publicOrigin: PUBLIC_ORIGIN,
      }))
    }

    securityHeaders(reply, nonce, false, true)
    return reply.type('text/html; charset=utf-8').send(webWatchPageHTML({
      code,
      roomName: room.name || 'Комната Plink',
      mediaTitle: mediaTitleFromMediaItem(room.mediaItem),
      target,
      nonce,
      publicOrigin: PUBLIC_ORIGIN,
    }))
  })

  // —— Plink+ на сайте ——
  fastify.get('/plus', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce, true)
    reply.header('Cache-Control', 'no-store')
    return reply.type('text/html; charset=utf-8').send(plusLanding(nonce))
  })

  fastify.get('/plus/success', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    return reply.type('text/html; charset=utf-8').send(plusSuccessLanding(nonce))
  })

  // —— Юридические и справочные страницы ——
  //
  // Приложение ссылается сюда из пейвола и из настроек. Страницы обслуживаются
  // бэкендом, а не лендингом, потому что бэкенд — единственный origin, до
  // которого клиент дозванивается по определению; App Review 3.1.2 требует, чтобы
  // ссылки на Условия и Конфиденциальность у подписочного приложения открывались.
  // Кэш — сутки: текст меняется редко, но не должен застревать у CDN навсегда.
  fastify.get('/terms', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    reply.header('Cache-Control', 'public, max-age=86400')
    return reply.type('text/html; charset=utf-8').send(legalLanding(nonce, TERMS))
  })

  fastify.get('/privacy', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    reply.header('Cache-Control', 'public, max-age=86400')
    return reply.type('text/html; charset=utf-8').send(legalLanding(nonce, PRIVACY))
  })

  fastify.get('/support', async (_req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    reply.header('Cache-Control', 'public, max-age=86400')
    return reply.type('text/html; charset=utf-8').send(supportLanding(nonce))
  })

  // —— Лендинг профиля ——
  fastify.get<{ Params: { username: string } }>('/u/:username', async (req, reply) => {
    const nonce = newNonce()
    securityHeaders(reply, nonce)
    // Тот же кейс, что и /r/:code — имя профиля меняется, кэшировать нельзя.
    reply.header('Cache-Control', 'no-store')
    const username = String(req.params.username ?? '')

    if (!USERNAME_RE.test(username)) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce,
        title: 'Plink — профиль не найден',
        heading: 'Профиль не найден',
        subheading: 'Проверьте ссылку.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/u/${encodeURIComponent(username)}`,
      }))
    }

    const user = await prisma.user.findFirst({
      where: { username, deletedAt: null, shadowbanned: false },
      // Поля bio в схеме нет.
      select: { displayName: true, username: true },
    })

    if (!user) {
      return reply.code(404).type('text/html; charset=utf-8').send(landing({
        nonce,
        title: 'Plink — профиль не найден',
        heading: 'Профиль не найден',
        subheading: 'Возможно, аккаунт удалён.',
        ogImage: `${PUBLIC_ORIGIN}/og/default.png`,
        canonical: `${PUBLIC_ORIGIN}/u/${username}`,
      }))
    }

    const display = user.displayName || user.username
    return reply.type('text/html; charset=utf-8').send(landing({
      nonce,
      title: `${display} в Plink`,
      heading: display,
      subheading: 'Смотрите вместе в Plink.',
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
      // mediaTitle принадлежит WatchHistory, а не Room.
      select: { name: true, mediaItem: true },
    })
    return sendOG(reply, room?.name || 'Комната Plink',
      room?.mediaItem || 'Присоединяйтесь к просмотру')
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
