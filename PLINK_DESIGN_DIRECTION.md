# Plink — дизайн-направление (зафиксировано владельцем 26.07.2026)

Этот файл — источник истины по дизайну для будущих сессий. Референс-промты
владельца (с motionsites.ai / designrocket.io) пересказаны здесь по существу —
в чате новой сессии их НЕ будет.

## Бренд-развязка (решение владельца)

- **Сайт (лендинги web.ts)** — ЯРКИЙ и кинематографичный, как приложение внутри.
- **Иконка приложения + сплэш + экран входа + онбординг** — бренд-шелл эталона
  `brand/source/reference.png`: фон `#010008`, фиолетовый знак play
  (`#8f44f0 → #4016ea`), вордмарк PLINK и теглайн «СМОТРИМ ВМЕСТЕ». Второго
  акцента нет: teal-капля в духе Rave/Hearo снята 02.09.2026 вместе со старым
  шеллом.
- Внутри приложения цвет живёт в живых темах (Aurora/Cosmos/Magma/Verdant) —
  бренд-шелл к ним не привязывается.

## Жёсткое техническое ограничение сайта

Строгий CSP: `default-src 'none'`, скрипты только inline с nonce.
**НИКАКИХ CDN** (React/Tailwind/Framer Motion из промтов не брать as-is),
**никаких внешних шрифтов** (Google Fonts запрещён) — сериф = системный
`'Didot','Bodoni 72','Playfair Display',Georgia,serif` italic. Все приёмы
референсов воспроизводятся чистым CSS/JS — уже сделано в
`backend/src/routes/web.ts` (v5, см. блок `<style>`).

## Реализованная дизайн-система v5 (web.ts)

- Палитра: чёрный #050505, ink #f5f7f6, акценты teal #19e0c0 / violet #7c5cff /
  amber #f5c26b (янтарь — точечно: штампы, флаги, ошибки).
- **Liquid glass** (1-в-1 приём из референса): `.lg`/`.lg-s` — rgba(255,255,255,.012)
  - luminosity blend + backdrop-blur 8/40px + светящаяся градиентная кромка через
    `padding:1.4px` + mask-composite:exclude.
- **Дисплей-типографика**: италик-сериф clamp(46-96px), letter-spacing −0.04em,
  line-height 0.95; градиентный `.accent` (teal→violet) через background-clip:text.
- **Пословный blur-in** `.bw`: keyframes blur 10px→4px→0, y 46→−5→0,
  easing cubic-bezier(.16,1,.3,1), stagger 100ms (серверный хелпер `blurWords()`).
- **Живой фон**: 3 цветные орбы-ауроры (blur 90px, 34-52s дрейф, отрицательные
  delay), луч-conic, зерно feTurbulence data-URI (mix-blend overlay, animation
  steps), виньетка, **spotlight за курсором** (radial-gradient по --sx/--sy,
  mix-blend screen, только pointer:fine).
- Навбар — плавающая стеклянная капсула top:16px по центру, белый pill-CTA.
- Бейдж `LIVE` — стеклянная капсула с белым чипом (референс-паттерн «New»).
- Карточки-возможности: стекло, min-height, иконка-квадрат слева + чипы-теги
  справа + большой сериф-титул снизу (структура из промта Space-Travel).
- Билет с кодом (фирменный элемент инвайта), партнёрская сериф-строка платформ,
  reduce-motion уважается везде, scroll-reveal через IntersectionObserver.

## Из референс-промтов ЕЩЁ НЕ реализовано (идеи на будущее)

1. **Фоновые видео с JS-кроссфейдом** (FadingVideo: rAF-фейд opacity, FADE 500ms,
   fade-out за 0.55s до конца, loop вручную через ended) — нужны видео-ассеты;
   у нас вместо этого CSS-аврора. Если появятся ассеты — самохост, не CDN.
2. **Cursor-spotlight reveal второй картинки** (промт Lithos): канвас рисует
   radial-gradient маску по курсору (r=260, стопы 1/.75/.4/.12/0), toDataURL →
   mask-image на слое с другим изображением; lerp-сглаживание 0.1.
3. Гигантский фоновый текст с динамическим scaleY по innerHeight (промт 404).
4. 3D-tilt мокапа: perspective 1100-1200px, rotateX/Y ≤ 12°, translateZ 24px,
   блик radial по --gx/--gy — каркас .phone-wrap уже есть в web.ts.
5. Магнитные кнопки, sticky-scroll секции, -webkit-box-reflect отражение под
   мокапом.

## Иконка приложения

Источник — `brand/` (см. `brand/README.md`): знак PLINK восстановлен 1:1 с
эталонного макета `brand/source/reference.png` — фиолетовая стрелка «play»
(светлая стрелка A `#8f44f0→#4016ea` + тёмный хвост B `#2c0688→#500e9d`) на
фоне `#010008`. Наборы иконок для iOS/iPadOS, Android, Windows, macOS, Linux и
веба лежат в `brand/platforms/`; iOS-набор уже стоит в `AppIcon.appiconset`
(1024 universal RGB без альфы + dark прозрачная + tinted серая). Цвета знака
постоянные, тема приложения красит только фон и гало вокруг него. Пересборка —
`brand/tools/gen_icons.py`, геометрия для SwiftUI — `brand/tools/gen_swift.py`
→ `Features/Brand/PlinkBrandGeometry.swift`.

## Сплэш, вход и онбординг (iOS)

- `Features/Brand/PlinkShell.swift` — `enum PlinkShell` (палитра шелла:
  background `#010008`, surface/surfaceLift, text/muted, accent `#8F44F0`,
  accentSoft, deep `#4016EA`, warning, hairline/specular) и
  `PlinkShellBackground(glowCenter:glowStrength:)` — дышащее сияние с гейтами
  Reduce Motion / Reduce Transparency / `plinkFreezeAnimations`.
- `Features/Brand/PlinkBrandMark.swift` — `PlinkBrandMark`, `PlinkWordmark`,
  `PlinkTagline`, `PlinkLockup` (знак + вордмарк + теглайн эталона 1:1),
  `PlinkAppIconTile`. Геометрия знака — `PlinkBrandGeometry.swift` из
  `brand/tools/gen_swift.py`.
- `Features/Auth2026/AuthChrome.swift` — общая хрома входа:
  `AuthPrimaryButtonStyle` (градиент акцента, спекуляр сверху),
  `AuthInlineNotice`, `LegalConsentFooter`.
- `Features/Auth2026/AuthLaunchGate.swift` — `PlinkSplashView` (лок-ап по
  центру, дышит только знак); `PlinkAuthScreen.swift` — вход, регистрация,
  сброс пароля на той же палитре, шапка = лок-ап.
- `Features/Onboarding2026/OnboardingFlow.swift` — три живых экрана: стена
  реальных постеров полки Иви/PREMIER (по сети, как на Главной), скриншоты
  разделов «Комнаты» и «Чаты» в рамке устройства, запрос уведомлений.
  Лицензии и границы — `ios/ART_ASSET_LICENSES.md`.

Играть цветом шелла = менять токены `PlinkShell` и `PlinkBrandPalette`.
Третьей палитры (`PlinkTheatre`, `SplashPalette`, `ProjectorBeamBackground`)
больше нет — не заводить заново.
