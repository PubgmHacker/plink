#!/usr/bin/env python3
"""Три направления иконки Plink, каждое в 1024/180/120/60 px.

Иконка живёт на домашнем экране рядом с Rave, Teleparty, Kast и Discord —
все они тёмно-синие с белым значком. Поэтому силуэт важнее детали: решения
здесь приняты «как это выглядит в 60 px», а не «как в 1024».

Общие правила (иначе иконка умирает на маленьком размере):
  • никаких тонких линий и текста;
  • одна крупная форма, читаемая силуэтом;
  • контраст к тёмному И светлому фону — отсюда светлая подложка-градиент,
    а не чёрная (текущая иконка на тёмном экране пропадает).
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import pathlib
import math

S = 1024
OUT = pathlib.Path("/tmp/plink-icons")
OUT.mkdir(parents=True, exist_ok=True)

# Палитра ЗНАКА — те же значения, что в PlinkBrandMark.swift (enum PlinkBrand).
#
# Редизайн 04.08.2026: направление A больше НЕ синее. Синий в Plink — одна из
# тем продукта (electric/cosmos), рядом с ней живут verdant, magma, aurora,
# bloom, ember, violet. Знак с синим корпусом означал, что человек с темой
# Magma видит на иконке и на входе чужой цвет. Корпус теперь графитовый, а
# единственное цветное пятно — ТЁПЛЫЙ СВЕТ ЭКРАНА: он универсален (включённый
# экран тёплый при любой теме) и это постоянный цвет бренда.
#
# Побочная выгода: Rave, Teleparty, Kast и Discord все тёмно-синие. Графит с
# тёплым светом отличает нас сильнее, чем ещё один синий квадрат.
GRAPHITE_LIFT = (58, 60, 66)    # верх корпуса
GRAPHITE_DEEP = (22, 23, 27)    # низ корпуса
INK = (8, 9, 11)                # «темнота зала»: силуэты и диван
SCREEN = (242, 244, 243)
WARM = (255, 214, 148)          # тёплый свет экрана
WARM_HOT = (255, 240, 214)

# Пропорция видимого кадра между полосами летербокса. Дублирована в
# `PlinkBrandMark.frameAspect` (Swift) — иконка и знак в приложении обязаны быть
# одной вещью. 2.35:1 — «синемаскоп», то, как выглядит кино; сам корпус экрана
# при 0.54×0.31 даёт лишь 1.74:1, поэтому «кино» из него делают именно полосы.
FRAME_ASPECT = 2.35

# Направления B и C — эксперименты, оставлены для сравнения силуэтов и живут
# на своей синей палитре. В продукт идёт A.
ACCENT = (46, 123, 255)
ACCENT_DEEP = (12, 40, 120)
ACCENT_NIGHT = (8, 20, 56)


def vertical_gradient(size, top, bottom):
    """Вертикальный градиент — база всех трёх направлений."""
    img = Image.new("RGB", (1, size), top)
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img.resize((size, size), Image.BICUBIC)


def radial_glow(size, center, radius, color, strength=1.0):
    """Мягкое свечение: рисуем пятно и размываем. Так свет от экрана
    выглядит светом, а не залитым кругом."""
    layer = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=int(255 * strength))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    tint = Image.new("RGB", (size, size), color)
    return tint, layer


# ─────────────────────────────────────────────────────────────────────────
# A. «Диван» — направление владельца: двое перед светящимся экраном.
#    Тёплый свет на графите: сцена читается как «смотрим вместе» без единой
#    буквы и не принадлежит ни одной теме продукта.
# ─────────────────────────────────────────────────────────────────────────
def direction_couch(with_wordmark: bool = False):
    # Верх корпуса заметно светлее низа: на домашнем экране iOS затемняет
    # иконку своим наложением, и слишком тёмный градиент читается пятном
    # рядом с системными иконками.
    img = vertical_gradient(S, GRAPHITE_LIFT, GRAPHITE_DEEP)
    d = ImageDraw.Draw(img)

    # Экран — источник света. Ширина 0.54, а не 0.60: маска-суперэллипс iOS
    # срезает углы, и широкий экран прижимался к самому краю иконки.
    sw, sh = int(S * 0.54), int(S * 0.31)
    sx, sy = (S - sw) // 2, int(S * 0.185)

    tint, mask = radial_glow(S, (S // 2, sy + sh // 2), int(S * 0.42), WARM, 0.85)
    img = Image.composite(tint, img, mask.point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(img)

    # На экране — КАДР, а не пустая заливка (правка 04.08.2026): ровный
    # светлый прямоугольник читался ВЫКЛЮЧЕННЫМ экраном, то есть ровно
    # противоположным тому, что знак должен говорить.
    #
    # Сюжетом сначала был закат над горизонтом (две зоны и диск). Кадр
    # появился, но прочли его как «солнце»: непонятный предмет, на просмотр не
    # похоже. Сюжет оказался СЛИШКОМ конкретным — знак не должен заставлять
    # разгадывать, что нарисовано.
    #
    # Теперь важно не «что показывают», а что экран ВЫГЛЯДИТ ВКЛЮЧЁННЫМ.
    # Признак идущего фильма, узнаваемый мгновенно и без сюжета, — ЛЕТЕРБОКС,
    # чёрные полосы сверху и снизу. Между ними тёплый свет с пятном по центру:
    # кадр светит, но ничего конкретного не изображает.
    #
    # Значения совпадают с `screenFace` в PlinkBrandMark.swift (пропорция кадра
    # 2.35:1, пятно чуть выше середины): иконка и знак внутри приложения обязаны
    # быть одной вещью.
    #
    # Логотип чужого сервиса (YouTube/VK/Rutube) здесь не годится — это
    # товарный знак другой компании внутри нашего, то есть заявка на
    # несуществующее партнёрство (App Review 5.2.5), плюс знак стал бы
    # принадлежать одной площадке из нескольких.
    screen = Image.new("RGB", (sw, sh), WARM)
    # Тёплый свет кадра: ярче к середине, гаснет к краям — так читается
    # подсветка, а не плоская заливка. Пятно рисуем в квадрате со стороной по
    # большей стороне экрана и вырезаем нужный прямоугольник: radial_glow
    # работает только с квадратом.
    span = max(sw, sh)
    glow_tint, glow_mask = radial_glow(
        span, (span // 2, int(span * 0.46)), int(sh * 0.62), WARM_HOT, 1.0
    )
    box = ((span - sw) // 2, (span - sh) // 2)
    crop = (box[0], box[1], box[0] + sw, box[1] + sh)
    screen.paste(glow_tint.crop(crop), (0, 0), glow_mask.crop(crop))
    sd = ImageDraw.Draw(screen)
    # Летербокс — то самое, что делает светящийся прямоугольник «идущим
    # фильмом». Толщина ВЫВОДИТСЯ из пропорции кадра, а не задаётся процентом:
    # раньше стояло 15% высоты, а комментарий обещал 2.35:1, хотя выходило
    # 2.49:1. Так же сделано в screenFace (PlinkBrandMark.swift).
    bar = max(1, int(round((sh - sw / FRAME_ASPECT) / 2)))
    sd.rectangle([0, 0, sw, bar], fill=INK)
    sd.rectangle([0, sh - bar, sw, sh], fill=INK)

    mask_screen = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask_screen).rounded_rectangle(
        [0, 0, sw - 1, sh - 1], radius=int(S * 0.035), fill=255
    )
    img.paste(screen, (sx, sy), mask_screen)

    d = ImageDraw.Draw(img)
    if with_wordmark:
        label = "PLINK"
        target_w = int(sw * 0.74)
        font = None
        for path in (
            "/System/Library/Fonts/SFNSRounded.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/HelveticaNeue.ttc",
        ):
            if not pathlib.Path(path).exists():
                continue
            # Подбираем кегль под ширину экрана, а не задаём числом: у разных
            # шрифтов метрики отличаются, и «на глаз» надпись уехала бы.
            for size in range(int(sh * 0.9), 10, -2):
                try:
                    cand = ImageFont.truetype(path, size)
                except OSError:
                    break
                box = d.textbbox((0, 0), label, font=cand, stroke_width=0)
                if box[2] - box[0] <= target_w:
                    font = cand
                    break
            if font:
                break

        if font:
            box = d.textbbox((0, 0), label, font=font)
            tx = sx + (sw - (box[2] - box[0])) // 2 - box[0]
            ty = sy + (sh - (box[3] - box[1])) // 2 - box[1]
            # Тёмная надпись на светлом экране: свет остаётся светом.
            d.text((tx, ty), label, font=font, fill=INK)

    # Два силуэта: круг-голова + плечи. Заливка цветом «темноты зала» —
    # фигуры «вырезаны» из света, поэтому силуэт читаем и в 60 px.
    body = INK
    head_r = int(S * 0.082)
    for cx in (int(S * 0.355), int(S * 0.645)):
        cy = int(S * 0.615)
        d.ellipse([cx - head_r, cy - head_r, cx + head_r, cy + head_r], fill=body)
        bw, bh = int(S * 0.25), int(S * 0.23)
        d.rounded_rectangle(
            [cx - bw // 2, cy + int(head_r * 0.55), cx + bw // 2, cy + bh],
            radius=int(S * 0.082), fill=body,
        )

    # Диван — одна плотная полоса внизу, без ножек и деталей. Не доходит до
    # краёв: иначе маска iOS срезает её концы.
    d.rounded_rectangle(
        [int(S * 0.155), int(S * 0.795), int(S * 0.845), int(S * 0.93)],
        radius=int(S * 0.05), fill=INK,
    )
    return img


# ─────────────────────────────────────────────────────────────────────────
# B. «Связь» — абстрактный знак синхронизации: два звена, сцепленных в
#    одно. Ничего не изображает буквально, зато уникален силуэтом.
# ─────────────────────────────────────────────────────────────────────────
def direction_link():
    img = vertical_gradient(S, (40, 108, 255), (10, 28, 96))
    tint, mask = radial_glow(S, (int(S * 0.32), int(S * 0.26)), int(S * 0.5), (150, 200, 255), 0.6)
    img = Image.composite(tint, img, mask.point(lambda v: int(v * 0.4)))

    # Первая версия рисовала два кольца внахлёст с перемычкой — в 60 px они
    # слились в нечитаемое «оо». Здесь звенья РАЗНЕСЕНЫ и сцеплены только
    # одним пересечением, а зазор между ними прорезан фоном: силуэт остаётся
    # двумя объектами даже когда деталь уже не видна.
    ring_w = int(S * 0.115)
    r = int(S * 0.20)
    left = (int(S * 0.385), S // 2)
    right = (int(S * 0.615), S // 2)

    link = Image.new("L", (S, S), 0)
    dl = ImageDraw.Draw(link)
    for cx, cy in (left, right):
        dl.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=ring_w)

    # Прорезаем зазор вокруг левого звена — правое «уходит под» него, и
    # сцепление читается как сцепление, а не как пятно.
    gap = Image.new("L", (S, S), 0)
    dg = ImageDraw.Draw(gap)
    pad = int(ring_w * 0.62)
    dg.ellipse(
        [left[0] - r - pad, left[1] - r - pad, left[0] + r + pad, left[1] + r + pad],
        outline=255, width=ring_w + pad * 2,
    )
    # Оставляем прорез только в правой половине: слева звенья не встречаются.
    keep = Image.new("L", (S, S), 0)
    ImageDraw.Draw(keep).rectangle([left[0] + int(r * 0.35), 0, S, S], fill=255)
    gap = Image.composite(gap, Image.new("L", (S, S), 0), keep)

    # Правое звено минус зазор, затем добавляем левое поверх.
    right_only = Image.new("L", (S, S), 0)
    ImageDraw.Draw(right_only).ellipse(
        [right[0] - r, right[1] - r, right[0] + r, right[1] + r], outline=255, width=ring_w
    )
    right_cut = Image.composite(Image.new("L", (S, S), 0), right_only, gap)

    left_only = Image.new("L", (S, S), 0)
    ImageDraw.Draw(left_only).ellipse(
        [left[0] - r, left[1] - r, left[0] + r, left[1] + r], outline=255, width=ring_w
    )

    combined = Image.new("L", (S, S), 0)
    combined.paste(right_cut, (0, 0), right_cut)
    combined.paste(left_only, (0, 0), left_only)

    plate = Image.new("RGB", (S, S), SCREEN)
    return Image.composite(plate, img, combined)


# ─────────────────────────────────────────────────────────────────────────
# C. «Плей из двух» — треугольник пуска, собранный из двух половин:
#    светлой и тёплой. Один знак, но читается как «двое».
# ─────────────────────────────────────────────────────────────────────────
def direction_play():
    img = vertical_gradient(S, (30, 84, 210), (9, 22, 70))
    tint, mask = radial_glow(S, (S // 2, int(S * 0.42)), int(S * 0.46), (120, 180, 255), 0.7)
    img = Image.composite(tint, img, mask.point(lambda v: int(v * 0.45)))

    # Первая версия была обычным треугольником пуска — такой знак есть у
    # каждого видеосервиса, силуэт неразличим. Здесь треугольник РАЗРЕЗАН
    # по диагонали на две дольки с зазором: в 1024 видно «двое», в 60 px
    # остаётся плей с характерной прорезью, которой нет у других.
    cx, cy = int(S * 0.53), S // 2
    rad = int(S * 0.31)
    pts = [
        (cx + rad, cy),
        (cx - rad * 0.80, cy - rad * 0.94),
        (cx - rad * 0.80, cy + rad * 0.94),
    ]

    tri = Image.new("L", (S, S), 0)
    dt = ImageDraw.Draw(tri)
    dt.polygon(pts, fill=255)
    dt.line(pts + [pts[0]], fill=255, width=int(S * 0.085), joint="curve")

    # Зазор режет треугольник ВДОЛЬ оси, от левого края к вершине: получаются
    # две дольки, сходящиеся в одну точку. Диагональный разрез (первая версия)
    # отсекал угол и читался как посторонняя полоса поверх знака.
    slit = Image.new("L", (S, S), 0)
    ds = ImageDraw.Draw(slit)
    w = int(S * 0.040)
    ds.line([(cx - rad * 0.95, cy), (cx + rad * 0.98, cy)], fill=255, width=w)
    tri = Image.composite(Image.new("L", (S, S), 0), tri, slit)

    # Верхняя долька тёплая, нижняя — свет экрана: два зрителя в одном знаке.
    top = Image.new("RGB", (S, S), WARM_HOT)
    bot = Image.new("RGB", (S, S), SCREEN)
    split = Image.new("L", (S, S), 0)
    ImageDraw.Draw(split).rectangle([0, 0, S, cy], fill=255)
    fill = Image.composite(top, bot, split)

    return Image.composite(fill, img, tri)


def emit(img, name, small_img=None, wordmark_min_px=120):
    """1024 — исходник, остальные — то, что реально видит человек.

    `small_img` — вариант без надписи для мелких размеров. Уменьшать картинку
    с текстом до 60 px нельзя: буквы превращаются в грязь и пачкают световое
    пятно, ради которого иконка и работает. Ниже `wordmark_min_px` берём
    версию без надписи.
    """
    img = img.convert("RGB")
    img.save(OUT / f"{name}-1024.png")
    fallback = (small_img or img).convert("RGB")
    for px in (180, 120, 60):
        source = img if px >= wordmark_min_px else fallback
        source.resize((px, px), Image.LANCZOS).save(OUT / f"{name}-{px}.png")
    return img


if __name__ == "__main__":
    # A: на экране внутри иконки — надпись PLINK (крупные размеры) и чистый
    # свет (мелкие). Оба варианта складываем рядом, чтобы было что сравнить.
    plain = direction_couch(with_wordmark=False)
    emit(direction_couch(with_wordmark=True), "A-couch", small_img=plain)
    emit(plain, "A-couch-plain")
    print("rendered A-couch (+plain)")

    for fn, name in (
        (direction_link, "B-link"),
        (direction_play, "C-play"),
    ):
        emit(fn(), name)
        print("rendered", name)
