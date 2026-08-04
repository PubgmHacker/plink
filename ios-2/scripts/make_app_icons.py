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

from PIL import Image, ImageDraw, ImageFilter
import pathlib
import math

S = 1024
OUT = pathlib.Path("/tmp/plink-icons")
OUT.mkdir(parents=True, exist_ok=True)

# Палитра из приложения: акцент #2E7BFF, свет экрана #F2F4F3.
ACCENT = (46, 123, 255)
ACCENT_DEEP = (12, 40, 120)
ACCENT_NIGHT = (8, 20, 56)
SCREEN = (242, 244, 243)
WARM = (255, 214, 148)   # тёплый свет экрана — против холодного синего
WARM_HOT = (255, 236, 205)


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
#    Тёплый свет против холодного синего: сцена читается как «смотрим
#    вместе» без единой буквы.
# ─────────────────────────────────────────────────────────────────────────
def direction_couch():
    img = vertical_gradient(S, (26, 62, 150), ACCENT_NIGHT)
    d = ImageDraw.Draw(img)

    # Экран — источник света, крупный прямоугольник в верхней трети.
    sw, sh = int(S * 0.60), int(S * 0.34)
    sx, sy = (S - sw) // 2, int(S * 0.16)

    tint, mask = radial_glow(S, (S // 2, sy + sh // 2), int(S * 0.42), WARM, 0.85)
    img = Image.composite(tint, img, mask.point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle([sx, sy, sx + sw, sy + sh], radius=int(S * 0.035), fill=WARM_HOT)

    # Два силуэта: круг-голова + плечи. Заливка цветом фона — фигуры
    # «вырезаны» из света, поэтому силуэт остаётся читаемым в 60 px.
    body = (7, 17, 48)
    head_r = int(S * 0.085)
    for cx in (int(S * 0.345), int(S * 0.655)):
        cy = int(S * 0.605)
        d.ellipse([cx - head_r, cy - head_r, cx + head_r, cy + head_r], fill=body)
        bw, bh = int(S * 0.26), int(S * 0.24)
        d.rounded_rectangle(
            [cx - bw // 2, cy + int(head_r * 0.55), cx + bw // 2, cy + bh],
            radius=int(S * 0.085), fill=body,
        )

    # Диван — одна плотная полоса внизу, без ножек и деталей.
    d.rounded_rectangle(
        [int(S * 0.13), int(S * 0.80), int(S * 0.87), int(S * 0.95)],
        radius=int(S * 0.055), fill=(5, 13, 38),
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


def emit(img, name):
    """1024 — исходник, остальные — то, что реально видит человек."""
    img = img.convert("RGB")
    img.save(OUT / f"{name}-1024.png")
    for px in (180, 120, 60):
        img.resize((px, px), Image.LANCZOS).save(OUT / f"{name}-{px}.png")
    return img


if __name__ == "__main__":
    for fn, name in (
        (direction_couch, "A-couch"),
        (direction_link, "B-link"),
        (direction_play, "C-play"),
    ):
        emit(fn(), name)
        print("rendered", name)
