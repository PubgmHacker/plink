#!/usr/bin/env python3
"""Собирает стену киноафиш для фона экрана входа.

ПОЧЕМУ АФИШИ ОРИГИНАЛЬНЫЕ, А НЕ «КАК У NETFLIX»

Просьба была прямая: настоящие превью фильмов, современные и поярче. Первая
часть невыполнима, и это не осторожность, а закрытая дверь:

  • Постер современного фильма — объект авторского права студии. Декоративный
    фон в чужом приложении не fair use: использование коммерческое и не
    трансформирующее.
  • App Review 5.2 требует, чтобы приложение подавала сторона, которой права
    принадлежат или лицензированы. Netflix показывает эти постеры, потому что
    лицензировал сам контент; у Plink такой лицензии нет.
  • «Грузим по сети, не бандлим» — не аргумент: он про распространение, а не про
    право показывать. Проект этот путь уже проходил (постеры с image.tmdb.org) и
    откатывал, см. ART_ASSET_LICENSES.md.

Афиши общественного достояния (1925–1929) пробовали и отвергли по делу: они
читаются старьём, а продукт современный. Вывод — не «взять чужое посвежее», а
НАРИСОВАТЬ СВОЁ так, чтобы держало современную планку.

ЧТО ЗДЕСЬ РИСУЕТСЯ

Двенадцать афиш, каждая — своя палитра и свой сюжет из восьми шаблонов
(горизонт, силуэт в контражуре, туманность, диагональный раскол, город, скорость,
портал, волна). Это не «процедурная текстура»: у каждой афиши есть композиция и
фокус, потому что постер узнаётся именно по ним.

Цвет НЕ приглушается. Прошлая версия сводила всё к тёплому монотону (насыщенность
30%), и именно от этого стена выглядела архивной. Здесь палитры насыщенные —
электрик, магента, амбер, тил, вайолет, — а связь с продуктом держится общей
глубокой базой и единой оптикой, а не обесцвечиванием.

СТЕКЛО ЗАПЕЧЕНО В АССЕТ

У каждой афиши скруглённые углы и стеклянный блик (диагональная полоса +
подсветка верхней кромки). Это ликвид-гласс, доставшийся бесплатно: 30 живых
`glassEffect` на фоне стоили бы кадров, а запечённый блик — ноль. Бегущий
специальный отсвет добавляется уже в рантайме одним слоем (см. `PosterWall`).

НАКЛОН ДЕЛАЕТСЯ В SWIFT, А НЕ ЗДЕСЬ

Полотно собирается ровной сеткой, а по диагонали его разворачивает
`rotationEffect` в `PosterWall`. Запекать наклон в ассет нельзя: при повороте
готовой картинки края придётся чем-то добивать, а поворот живого слоя просто
берёт то, что уже есть за кадром.

Важно не спутать две разные вещи: «кирпичной кладкой» когда-то читалась сетка со
сдвигом ряда на ПОЛБЛОКА — это перевязка. Наклон ровной сетки перевязки не
создаёт, ряды остаются рядами, просто идут по диагонали.

ЗАПУСК

    pip3 install pillow          # единственная зависимость
    python3 scripts/make_poster_wall.py

Сети не требует и ничего не скачивает — всё рисуется на месте, поэтому результат
не зависит ни от Commons, ни от кэша, ни от того, что там сегодня с лицензиями.
Обычная сборка приложения скрипт не запускает: готовое полотно лежит в репозитории.

ГЕОМЕТРИЯ ЖИВЁТ В ДВУХ МЕСТАХ

PW/PH/COLS/ROWS/GAP ниже дублированы в `PosterWall` (AnimatedPosterMosaic.swift):
Swift выводит из них пропорцию полотна, чтобы не растянуть афиши. Меняешь сетку
здесь — поправь и там.
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json
import math
import pathlib
import random

OUT = pathlib.Path(__file__).resolve().parent.parent / (
    "Plink/Resources/Assets.xcassets/AuthPosterWall.imageset"
)

# Геометрия стены. Колонки и строки РОВНЫЕ: наклон даёт Swift, см. заголовок.
PW, PH = 300, 450          # афиша 2:3
COLS, ROWS = 6, 5
GAP = 24
CORNER = 20                # скругление афиши: «превью», а не голый прямоугольник

# Фон полотна в зазорах — почти чёрный с холодным уклоном, как V4.canvas.
VOID = (7, 9, 12)

# Яркость афиши варьируется чуть-чуть. Прошлая версия гуляла в 52–78% и делала
# стену пятнистой; когда цвет насыщенный, разброса в пару процентов достаточно,
# чтобы стена не выглядела печатным листом.
BRIGHT_MIN, BRIGHT_MAX = 0.88, 1.0

# Палитры: (тень, основной, свет). Насыщенные, но все с глубокой тенью — именно
# общая глубина, а не общий оттенок, связывает стену с остальным продуктом.
PALETTES = [
    ((4, 10, 38), (24, 78, 226), (128, 224, 255)),    # электрик
    ((30, 4, 30), (194, 34, 152), (255, 156, 232)),   # магента
    ((30, 13, 3), (224, 122, 22), (255, 222, 146)),   # амбер
    ((2, 26, 26), (20, 182, 162), (152, 255, 236)),   # тил
    ((14, 6, 36), (112, 52, 232), (204, 176, 255)),   # вайолет
    ((30, 5, 11), (212, 32, 62), (255, 164, 152)),    # кримсон
    ((6, 16, 32), (62, 142, 232), (204, 242, 255)),   # айс
    ((8, 24, 7), (122, 202, 42), (222, 255, 174)),    # лайм
    ((28, 8, 20), (240, 82, 62), (255, 204, 124)),    # закат
    ((6, 14, 30), (0, 182, 222), (255, 124, 202)),    # циан-пинк
    ((12, 10, 6), (192, 152, 42), (255, 242, 192)),   # золото
    ((10, 6, 28), (82, 62, 222), (92, 232, 255)),     # индиго-циан
]


# ─── Мелкие помощники ───────────────────────────────────────────────────────


def lerp_color(a, b, f):
    return tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3))


def vertical_gradient(stops):
    """Вертикальный градиент по опорным точкам [(позиция 0..1, цвет), ...]."""
    img = Image.new("RGB", (PW, PH))
    draw = ImageDraw.Draw(img)
    for y in range(PH):
        t = y / (PH - 1)
        color = stops[-1][1]
        for i in range(len(stops) - 1):
            (pa, ca), (pb, cb) = stops[i], stops[i + 1]
            if pa <= t <= pb:
                f = 0.0 if pb == pa else (t - pa) / (pb - pa)
                color = lerp_color(ca, cb, f)
                break
        draw.line([(0, y), (PW, y)], fill=color)
    return img


def add_glow(img, center, radius, color, strength=1.0):
    """Свечение поверх кадра — ЭКРАННЫМ смешиванием, а не заливкой.

    Заливка выбивает то, что под ней, и свет выглядит наклейкой. Screen только
    добавляет яркость, поэтому под свечением остаётся видно композицию.
    """
    mask = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(mask).ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=255,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.55))
    if strength != 1.0:
        mask = mask.point(lambda v: int(v * strength))
    layer = Image.new("RGB", (PW, PH), (0, 0, 0))
    layer.paste(Image.new("RGB", (PW, PH), color), (0, 0), mask)
    return ImageChops.screen(img, layer)


def fill_shape(img, points, color, blur=0):
    """Тёмный силуэт (или любая плотная форма) поверх кадра."""
    mask = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    out = img.copy()
    out.paste(Image.new("RGB", (PW, PH), color), (0, 0), mask)
    return out


def add_grain(img, rnd, amount=7):
    """Зерно: без него насыщенный градиент выглядит пластиковым баннером."""
    noise = Image.new("L", (PW, PH))
    noise.putdata([128 + rnd.randint(-amount, amount) for _ in range(PW * PH)])
    return ImageChops.overlay(img, noise.convert("RGB"))


def add_vignette(img, strength=0.45):
    """Виньетка внутри КАЖДОЙ афиши — так постер читается кадром, а не плиткой."""
    mask = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(mask).ellipse(
        [-PW * 0.30, -PH * 0.20, PW * 1.30, PH * 1.20], fill=255
    )
    mask = mask.filter(ImageFilter.GaussianBlur(PW * 0.22))
    dark = Image.new("RGB", (PW, PH), (0, 0, 0))
    faded = Image.blend(dark, img, 1.0 - strength)
    return Image.composite(img, faded, mask)


def add_gloss(img, rnd):
    """Стеклянный блик: диагональная полоса + подсветка верхней кромки.

    Это и есть ликвид-гласс на превью, запечённый в ассет. Живой `glassEffect`
    на тридцати плитках фона стоил бы кадров и ничего не добавил бы: стекло на
    неподвижной подложке всё равно читается блеском, а не рефракцией.
    """
    shift = rnd.uniform(-0.10, 0.10)
    band = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(band).polygon(
        [
            (PW * (-0.10 + shift), PH * 0.00),
            (PW * (0.52 + shift), PH * 0.00),
            (PW * (0.10 + shift), PH * 1.00),
            (PW * (-0.52 + shift), PH * 1.00),
        ],
        fill=255,
    )
    band = band.filter(ImageFilter.GaussianBlur(PW * 0.10)).point(
        lambda v: int(v * 0.16)
    )

    edge = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(edge).rectangle([0, 0, PW, PH * 0.055], fill=255)
    edge = edge.filter(ImageFilter.GaussianBlur(PW * 0.03)).point(
        lambda v: int(v * 0.22)
    )

    sheen = Image.new("RGB", (PW, PH), (0, 0, 0))
    white = Image.new("RGB", (PW, PH), (255, 255, 255))
    sheen.paste(white, (0, 0), band)
    sheen.paste(white, (0, 0), edge)
    return ImageChops.screen(img, sheen)


# ─── Сюжеты афиш ────────────────────────────────────────────────────────────
#
# Восемь шаблонов. Каждый — с композицией и фокусом: постер узнаётся по ним, а
# не по «фактуре». Ровная абстракция на этом месте снова читалась бы обоями.


def t_horizon(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient(
        [(0.0, lerp_color(mid, light, 0.35)), (0.52, mid), (1.0, shadow)]
    )
    sun_y = PH * rnd.uniform(0.40, 0.47)
    img = add_glow(img, (PW * 0.5, sun_y), PW * 0.34, light, 0.95)
    ground = PH * rnd.uniform(0.62, 0.68)
    img = fill_shape(
        img, [(0, ground), (PW, ground - PH * 0.02), (PW, PH), (0, PH)], (4, 5, 8)
    )
    return add_glow(img, (PW * 0.5, ground), PW * 0.42, light, 0.30)


def t_figure(pal, rnd):
    """Двое в контражуре — сюжет самого продукта: смотрят вместе.

    Первая версия рисовала одну фигуру трапецией от головы до низа кадра, и это
    читалось МОНАХОМ в балахоне: у человека есть плечи, то есть резкий уступ от
    шеи, а не плавный конус. Здесь плечи явные, и фигур две — на постере пара
    силуэтов сразу задаёт историю, одиночная фигура задаёт загадку.
    """
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, shadow), (0.52, mid), (1.0, shadow)])
    img = add_glow(img, (PW * 0.5, PH * 0.40), PW * 0.52, light, 0.85)

    floor = PH * 0.72
    img = fill_shape(
        img, [(0, floor), (PW, floor - PH * 0.015), (PW, PH), (0, PH)], (3, 4, 7)
    )
    img = add_glow(img, (PW * 0.5, floor), PW * 0.40, light, 0.22)

    for cx_frac, scale in ((0.38, 1.0), (0.62, 0.94)):
        cx = PW * cx_frac
        head_r = PW * 0.082 * scale
        head_cy = PH * 0.455
        shoulder_y = head_cy + head_r * 2.1
        half = PW * 0.115 * scale
        img = fill_shape(
            img,
            [
                (cx - half, floor + PH * 0.01),
                (cx - half * 0.94, shoulder_y),
                (cx - head_r * 1.15, shoulder_y - head_r * 0.30),
                (cx - head_r * 0.80, head_cy + head_r * 0.55),
                (cx + head_r * 0.80, head_cy + head_r * 0.55),
                (cx + head_r * 1.15, shoulder_y - head_r * 0.30),
                (cx + half * 0.94, shoulder_y),
                (cx + half, floor + PH * 0.01),
            ],
            (3, 4, 7),
        )
        mask = Image.new("L", (PW, PH), 0)
        ImageDraw.Draw(mask).ellipse(
            [cx - head_r, head_cy - head_r * 1.12,
             cx + head_r, head_cy + head_r * 1.12],
            fill=255,
        )
        img.paste(Image.new("RGB", (PW, PH), (3, 4, 7)), (0, 0), mask)
    return img


def t_nebula(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, shadow), (1.0, (2, 3, 6))])
    for i in range(7):
        ang = rnd.uniform(0, math.tau)
        dist = PW * rnd.uniform(0.05, 0.34)
        img = add_glow(
            img,
            (PW * 0.5 + math.cos(ang) * dist, PH * 0.46 + math.sin(ang) * dist * 1.3),
            PW * rnd.uniform(0.18, 0.40),
            mid if i % 2 else light,
            rnd.uniform(0.30, 0.60),
        )
    stars = Image.new("RGB", (PW, PH), (0, 0, 0))
    sd = ImageDraw.Draw(stars)
    for _ in range(90):
        x, y = rnd.randrange(PW), rnd.randrange(PH)
        v = rnd.randint(120, 255)
        sd.point((x, y), fill=(v, v, v))
    return ImageChops.screen(img, stars)


def t_split(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, mid), (1.0, shadow)])
    wedge = Image.new("L", (PW, PH), 0)
    off = PW * rnd.uniform(0.30, 0.50)
    ImageDraw.Draw(wedge).polygon(
        [(off, 0), (PW, 0), (PW, PH), (off - PW * 0.34, PH)], fill=255
    )
    other = vertical_gradient([(0.0, light), (1.0, mid)])
    img = Image.composite(other, img, wedge.filter(ImageFilter.GaussianBlur(1.2)))
    return add_glow(img, (off, PH * 0.5), PW * 0.30, light, 0.55)


def t_skyline(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient(
        [(0.0, shadow), (0.58, mid), (1.0, lerp_color(mid, light, 0.30))]
    )
    img = add_glow(img, (PW * rnd.uniform(0.3, 0.7), PH * 0.30), PW * 0.24, light, 0.80)
    base = PH * 0.74
    x = 0.0
    while x < PW:
        w = PW * rnd.uniform(0.09, 0.19)
        h = PH * rnd.uniform(0.10, 0.30)
        img = fill_shape(
            img, [(x, base - h), (x + w, base - h), (x + w, PH), (x, PH)], (4, 5, 9)
        )
        x += w + PW * 0.012
    return img


def t_speed(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, (3, 4, 8)), (0.5, shadow), (1.0, (3, 4, 8))])
    streaks = Image.new("RGB", (PW, PH), (0, 0, 0))
    sd = ImageDraw.Draw(streaks)
    for _ in range(16):
        y = rnd.uniform(0, PH)
        length = PW * rnd.uniform(0.35, 1.05)
        x0 = rnd.uniform(-PW * 0.2, PW)
        color = light if rnd.random() < 0.4 else mid
        sd.line(
            [(x0, y), (x0 + length, y - PH * 0.06)],
            fill=color,
            width=max(1, int(PH * rnd.uniform(0.004, 0.014))),
        )
    streaks = streaks.filter(ImageFilter.GaussianBlur(PW * 0.012))
    img = ImageChops.screen(img, streaks)
    return add_glow(img, (PW * 0.5, PH * 0.5), PW * 0.45, mid, 0.35)


def t_portal(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, shadow), (1.0, (2, 3, 6))])
    cy = PH * rnd.uniform(0.42, 0.50)
    for i, frac in enumerate((0.40, 0.30, 0.21, 0.13)):
        ring = Image.new("L", (PW, PH), 0)
        r = PW * frac
        ImageDraw.Draw(ring).ellipse(
            [PW * 0.5 - r, cy - r, PW * 0.5 + r, cy + r],
            outline=255,
            width=max(2, int(PW * 0.022)),
        )
        ring = ring.filter(ImageFilter.GaussianBlur(PW * 0.018))
        layer = Image.new("RGB", (PW, PH), (0, 0, 0))
        layer.paste(
            Image.new("RGB", (PW, PH), light if i % 2 else mid), (0, 0), ring
        )
        img = ImageChops.screen(img, layer)
    return add_glow(img, (PW * 0.5, cy), PW * 0.16, light, 0.9)


def t_wave(pal, rnd):
    shadow, mid, light = pal
    img = vertical_gradient([(0.0, shadow), (0.6, mid), (1.0, shadow)])
    for i in range(5):
        band = Image.new("L", (PW, PH), 0)
        bd = ImageDraw.Draw(band)
        base = PH * (0.22 + i * 0.14) + rnd.uniform(-PH * 0.02, PH * 0.02)
        amp = PH * rnd.uniform(0.03, 0.07)
        pts = [
            (x, base + math.sin(x / PW * math.tau * rnd.uniform(0.8, 1.4) + i) * amp)
            for x in range(0, PW + 8, 8)
        ]
        bd.line(pts, fill=255, width=max(2, int(PH * 0.012)))
        band = band.filter(ImageFilter.GaussianBlur(PW * 0.02))
        layer = Image.new("RGB", (PW, PH), (0, 0, 0))
        layer.paste(Image.new("RGB", (PW, PH), light if i % 2 else mid), (0, 0), band)
        img = ImageChops.screen(img, layer)
    return img


TEMPLATES = [
    t_horizon,
    t_figure,
    t_nebula,
    t_split,
    t_skyline,
    t_speed,
    t_portal,
    t_wave,
]


def add_title_block(img, pal, rnd):
    """Титул и строка титров — то, по чему постер узнаётся МГНОВЕННО.

    Без этого любая картинка 2:3 остаётся просто картинкой 2:3. Постер отличает
    не сюжет, а ВЁРСТКА: крупный титул в нижней трети, под ним россыпь мелких
    строк (студии, актёры, «в кино с такого-то»). Именно эту структуру глаз
    считывает как «афиша», даже когда текст нечитаем.

    Буквы не рисуем — рисуем их МАССУ полосами. На экране афиша шириной 126 pt
    да ещё и размытая: настоящий шрифт там всё равно превратится в кашу, а
    фальшивая латиница выглядела бы бессмысленным набором в углу. Полосы честнее
    и читаются ровно так, как надо.
    """
    _, mid, light = pal
    layer = Image.new("RGB", (PW, PH), (0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Титул: две-три строки разной длины, выключка по центру. Одна строка
    # читается подписью, четыре — абзацем; название фильма почти всегда 2–3.
    base = PH * rnd.uniform(0.62, 0.70)
    lines = rnd.choice((2, 2, 3))
    height = PH * rnd.uniform(0.052, 0.070)
    for i in range(lines):
        w = PW * rnd.uniform(0.34, 0.78)
        y = base + i * height * 1.22
        d.rounded_rectangle(
            [PW / 2 - w / 2, y, PW / 2 + w / 2, y + height],
            radius=height * 0.16,
            fill=(255, 255, 255),
        )

    # Титры: плотный мелкий кегль внизу. Держим их узкой колонкой по центру —
    # так это читается «блоком», а не строчкой текста.
    credit_y = PH * rnd.uniform(0.855, 0.885)
    for i in range(rnd.choice((2, 3))):
        w = PW * rnd.uniform(0.30, 0.62)
        y = credit_y + i * PH * 0.026
        d.rectangle(
            [PW / 2 - w / 2, y, PW / 2 + w / 2, y + PH * 0.011],
            fill=(215, 220, 235),
        )

    # Титул светится цветом афиши, а не белым: белый текст на насыщенном фоне
    # выглядит наклейкой поверх, а подсвеченный — частью кадра.
    tint = Image.new("RGB", (PW, PH), lerp_color(light, (255, 255, 255), 0.45))
    mask = layer.convert("L").point(lambda v: int(v * 0.90))
    out = img.copy()
    out.paste(tint, (0, 0), mask)

    # Подложка под текстом: без неё титул тонет, когда под ним светлая часть кадра.
    scrim = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(scrim).rectangle([0, PH * 0.56, PW, PH], fill=150)
    scrim = scrim.filter(ImageFilter.GaussianBlur(PH * 0.05))
    dark = Image.new("RGB", (PW, PH), (2, 3, 6))
    out = Image.composite(Image.blend(out, dark, 0.42), out, scrim)
    # Текст поверх подложки — иначе она же его и притушит.
    out.paste(tint, (0, 0), mask)
    return add_glow(out, (PW * 0.5, base + PH * 0.03), PW * 0.30, mid, 0.22)


def build_poster(index):
    """Одна афиша: сюжет + зерно + виньетка + вёрстка постера + стекло."""
    rnd = random.Random(1000 + index * 7)
    template = TEMPLATES[index % len(TEMPLATES)]
    palette = PALETTES[index % len(PALETTES)]
    img = template(palette, rnd)
    img = add_grain(img, rnd)
    img = add_vignette(img)
    img = add_title_block(img, palette, rnd)
    return add_gloss(img, rnd)


def plan_layout(count):
    """Какая афиша в какой ячейке. Детерминированно и без соседних повторов.

    Афиш двенадцать, ячеек тридцать, поэтому повторы неизбежны — вопрос лишь в
    том, где они стоят. Наивный «перетасовать и взять по порядку» ставил одну
    афишу в две соседние ячейки впритык, а стена из видимых повторов читается
    обоями, то есть тем самым узором, от которого ушли.

    Поэтому ячейки заполняются по порядку, и для каждой берётся первая афиша,
    которой ещё нет по соседству, включая ДИАГОНАЛИ: сетка наклонена, и
    диагональный повтор попадает в поле зрения целиком.
    """
    rnd = random.Random(11)
    pool = []
    while len(pool) < COLS * ROWS:
        batch = list(range(count))
        rnd.shuffle(batch)
        pool += batch

    grid = [None] * (COLS * ROWS)
    for i in range(COLS * ROWS):
        col, row = i % COLS, i // COLS
        taken = set()
        for dc, dr in ((-1, 0), (0, -1), (-1, -1), (1, -1)):
            c, r = col + dc, row + dr
            if 0 <= c < COLS and 0 <= r < ROWS:
                taken.add(grid[r * COLS + c])
        pick = next((p for p in pool if p not in taken), pool[0])
        pool.remove(pick)
        grid[i] = pick
    return grid


def main():
    posters = [build_poster(i) for i in range(len(PALETTES))]

    width = COLS * PW + GAP * (COLS + 1)
    height = ROWS * PH + GAP * (ROWS + 1)
    sheet = Image.new("RGB", (width, height), VOID)

    # Скругление — одной маской на все плитки, а не по афише: так углы гарантированно
    # одинаковые.
    corner = Image.new("L", (PW, PH), 0)
    ImageDraw.Draw(corner).rounded_rectangle([0, 0, PW - 1, PH - 1], CORNER, fill=255)

    layout = plan_layout(len(posters))
    for i, index in enumerate(layout):
        rnd = random.Random(i * 17 + 3)
        tile = posters[index]
        factor = BRIGHT_MIN + rnd.random() * (BRIGHT_MAX - BRIGHT_MIN)
        if factor < 1.0:
            tile = Image.blend(Image.new("RGB", (PW, PH), (0, 0, 0)), tile, factor)
        col, row = i % COLS, i // COLS
        sheet.paste(
            tile, (GAP + col * (PW + GAP), GAP + row * (PH + GAP)), corner
        )

    OUT.mkdir(parents=True, exist_ok=True)

    # Размеры экспорта считаются ОТ ПРОПОРЦИИ ПОЛОТНА, а не задаются руками:
    # литералы здесь однажды уже растянули афиши по горизонтали на 4.3%.
    def export(target_width, name, quality):
        target_height = round(target_width * height / width)
        sheet.resize((target_width, target_height), Image.LANCZOS).save(
            OUT / name, quality=quality, optimize=True
        )
        return target_width, target_height

    size1x = export(900, "wall.jpg", 88)
    size2x = export(1800, "wall@2x.jpg", 86)
    # @3x нужен: без него каталог тянет 2x на 3x-экранах, и афиши теряют детали —
    # ровно то, из-за чего затея с читаемыми превью теряет смысл.
    size3x = export(2700, "wall@3x.jpg", 84)

    (OUT / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": "wall.jpg", "idiom": "universal", "scale": "1x"},
            {"filename": "wall@2x.jpg", "idiom": "universal", "scale": "2x"},
            {"filename": "wall@3x.jpg", "idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

    print(f"собрана стена из {len(posters)} оригинальных афиш → {OUT}")
    print(f"  полотно {width}×{height} (пропорция {width / height:.4f})")
    for label, size in (("1x", size1x), ("2x", size2x), ("3x", size3x)):
        print(f"  {label}: {size[0]}×{size[1]} (пропорция {size[0] / size[1]:.4f})")
    print(f"  сюжеты: {', '.join(t.__name__[2:] for t in TEMPLATES)}")


if __name__ == "__main__":
    main()
