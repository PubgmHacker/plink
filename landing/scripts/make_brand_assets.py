#!/usr/bin/env python3
"""Иконки и OG-картинка лендинга — из того же знака, что и иконка приложения.

До этого лендинг жил со своим знаком (тёплый треугольник на чёрном), iOS — со
своим (мятный треугольник), то есть у продукта было две разные личности.
Здесь оба берутся из одного исходника: ios-2/.../AppIcon-1024.png.

Запуск:  python3 landing/scripts/make_brand_assets.py
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
PUBLIC = HERE.parent / "public"
SOURCE = (
    HERE.parent.parent
    / "ios-2/Plink/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)

VELVET = (10, 13, 20)


def rounded(img, radius_ratio=0.22):
    """Скругляем углы: на вебе маску iOS никто не применит."""
    size = img.size[0]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255
    )
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img.convert("RGB"), (0, 0), mask)
    return out


def load_font(size):
    """Системный шрифт macOS; если его нет — дефолтный, лишь бы не падать."""
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        if pathlib.Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def main():
    src = Image.open(SOURCE).convert("RGB")

    # Favicon: 16 px — это ~8 различимых пикселей, поэтому берём ту же
    # картинку, но без скругления на самых мелких (углы съедают силуэт).
    for px in (16, 32, 48):
        icon = src.resize((px, px), Image.LANCZOS)
        icon.save(PUBLIC / f"favicon-{px}x{px}.png")

    rounded(src, 0.23).resize((180, 180), Image.LANCZOS).save(
        PUBLIC / "apple-touch-icon.png"
    )

    # .ico с тремя размерами внутри — старые браузеры берут из него.
    src.resize((48, 48), Image.LANCZOS).save(
        PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)]
    )

    # OG: 1200x630, знак слева, текст справа. Никаких мелких деталей —
    # в лентах картинку сжимают до ~300 px по ширине.
    og = Image.new("RGB", (1200, 630), VELVET)

    glow = Image.new("L", (1200, 630), 0)
    ImageDraw.Draw(glow).ellipse([40, 90, 700, 620], fill=90)
    og = Image.composite(
        Image.new("RGB", (1200, 630), (30, 70, 170)),
        og,
        glow.filter(ImageFilter.GaussianBlur(150)),
    )

    mark = rounded(src, 0.23).resize((300, 300), Image.LANCZOS)
    og.paste(mark, (96, 165), mark)

    d = ImageDraw.Draw(og)
    d.text((466, 236), "Plink", font=load_font(112), fill=(242, 244, 243))
    d.text((472, 372), "Смотрите вместе — кадр в кадр", font=load_font(38),
           fill=(152, 163, 176))

    og.save(PUBLIC / "og-image.png")
    print("written:", ", ".join(
        p.name for p in sorted(PUBLIC.glob("favicon*"))
    ), "+ apple-touch-icon.png, og-image.png")


if __name__ == "__main__":
    main()
