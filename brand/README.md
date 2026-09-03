# Plink — фирменный знак

Знак PLINK: стрелка «play» из двух фигур — светлая стрелка (A) и тёмный хвост (B),
вордмарк PLINK, слоган **WATCH TOGETHER. ANYWHERE.** и подвал
**⊙ PLAYER · 💬 MESSENGER · ▤ REELS**. Всё восстановлено в векторе 1:1 с эталонного
макета (`source/reference.png`, 1056×1008): контуры знака сняты с растра и
описаны кривыми, литеры — скруглённые многоугольники, градиенты подогнаны по
восьми опорным точкам под цвета эталона.

Цвета бренда постоянные и от тем приложения не зависят: тема может красить
фон и гало **вокруг** знака, но не сам знак.

| Токен | Значение | Где |
|---|---|---|
| фон макета | `#010008` | лок-ап, og-афиша, манифест |
| стрелка, верх → низ | `#8f44f0 → #4016ea` | фигура A |
| хвост | `#2c0688 → #500e9d` | фигура B |
| кромка стрелки | `#eadfff` 60 % → 20 % | внутренний штрих A |
| вордмарк | `#f4f4f5 → #c2bfdb` | сверху вниз |
| слоган | `#8642d6 → #6a49d1 → #4189d2` | слева направо |
| акцент/иконки подвала | `#8F44F0` | mask-icon, подвал |

## Мастер-файлы

| Файл | Что это |
|---|---|
| `plink-lockup.svg`, `plink-lockup@2x.png` | полный лок-ап на фоне, как эталон |
| `plink-lockup-transparent.svg` | то же без фона |
| `plink-mark.svg`, `plink-mark-1024.png` | только знак (рамка 350×460 с полями) |
| `plink-mark-mono-white.svg`, `plink-mark-mono-black.svg` | одноцветный знак, хвост 55 % |
| `plink-wordmark.svg` | слово PLINK контурами |
| `plink-logo-horizontal.svg`, `plink-logo-horizontal-dark@2x.png` | знак + слово в строку |

## Иконки по платформам — `platforms/`

| Платформа | Содержимое | Куда ставить |
|---|---|---|
| `ios/AppIcon.appiconset` | 1024 универсальная + dark (прозрачная) + tinted (серая), `Contents.json` | `ios/Plink/Resources/Assets.xcassets/AppIcon.appiconset/` — уже установлено |
| `android/` | adaptive: `ic_launcher_{background,foreground,monochrome}` 432, `mipmap-anydpi-v26/*.xml`, legacy `ic_launcher`/`_round` mdpi…xxxhdpi, `play-store-512.png` | `app/src/main/res/` |
| `windows/` | `plink.ico` (16…256), тайлы MSIX `Square44/71/150/310`, `Wide310x150`, `SplashScreen`, `StoreLogo` ×100/200/400 % | `Assets/` пакета |
| `macos/` | `Plink.icns` + `Plink.iconset` (скруглённый квадрат macOS, тень) | `Contents/Resources/` |
| `linux/` | `hicolor/<size>/apps/plink.png` 16…512, `scalable/apps/plink.svg`, `plink.desktop` | `/usr/share/icons/hicolor`, `/usr/share/applications` |
| `web/` | favicon 16/32/48 + `.ico`, `apple-touch-icon` 180, `android-chrome` 192/512 maskable, `safari-pinned-tab.svg`, `og-image.png` 1200×630, `site.webmanifest` | `landing/public/` — уже установлено |

iPad использует тот же `AppIcon.appiconset` (idiom `universal`).

## Код

* iOS — `ios/Plink/Features/Brand/PlinkBrandGeometry.swift`: те же контуры и
  градиенты как `Shape`/`LinearGradient` (`PlinkMarkShapeA/B`,
  `PlinkMarkSilhouette`, `PlinkWordmarkShape`, `PlinkBrandPalette`).
  Файл **генерируется** (`tools/gen_swift.py`), руками не править.
* Бэкенд — `backend/src/routes/web.ts`: `appIconSVG()` и `ogSVG()` рисуют знак
  теми же контурами (`BRAND_MARK_A/B`, `BRAND_WORDMARK`).
* Лендинг — `landing/components/PlinkMark.tsx`.

## Как пересобрать

Нужны Python 3 с Pillow и numpy, `rsvg-convert` (librsvg) и `iconutil` (macOS).

```bash
python3 brand/tools/build_lockup.py            # source/lockup_ref.svg из JSON-источников (+ сравнение с эталоном в _build/)
python3 brand/tools/gen_icons.py brand/_build   # мастера и все платформенные наборы → _build/
python3 brand/tools/gen_swift.py                # → ios/Plink/Features/Brand/PlinkBrandGeometry.swift
```

`source/` — единственная правда: `mark_paths.json` (контуры A/B),
`glyphs_fit.json` (литеры), `grad_fit.json` (опоры градиентов),
`tag_med.json`/`foot_semi.json` (глифы слогана и подвала, SF Rounded),
`mask.png` (маска знака — из неё берётся рамка), `reference.png` (эталон).
После `gen_icons.py` скопировать нужные наборы из `_build/` в `platforms/` и по
местам установки.
