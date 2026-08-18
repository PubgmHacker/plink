#!/usr/bin/env python3
"""Landing favicons and OG image, generated from the same mark as the app icon.

The landing site used to carry its own mark (a warm triangle on black) while iOS
carried a different one (a mint triangle) — two visual identities for one product.
Both now derive from a single source: ios/.../AppIcon-1024.png.

Run:  python3 landing/scripts/make_brand_assets.py

Outputs are committed. The five icon outputs are pure resampling and reproduce byte for
byte on any machine; if one of them changes, a source asset changed or this script did,
and that difference is the thing to explain before committing it.

og-image.png is the exception, because it is the only output that rasterizes text. Its
glyph advances land differently across FreeType versions — measured: identical ink
coverage to the pixel, same glyph origins, but the line "Plink" ends 1 px earlier and
the subtitle 5 px earlier under FreeType 2.14.3 than under the version that produced
the committed file. That is a ~40 byte difference in the PNG and it is not a change to
the design. So: do not commit a regenerated og-image.png just because the bytes moved.
Diff the pixels, and if the mark, the glow and the ink extents all match, keep the
committed file.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
PUBLIC = HERE.parent / "public"
SOURCE = (
    HERE.parent.parent
    / "ios/Plink/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)
# The variant without the word PLINK on the screen. Below roughly 32 px the letters
# turn to mud and smear the pool of light the whole mark depends on, so the small
# favicons come from here instead of from the app icon.
SOURCE_PLAIN = HERE.parent.parent / "brand/plink-icon-plain-1024.png"

VELVET = (10, 13, 20)


def rounded(img, radius_ratio=0.22):
    """Round the corners ourselves — the web will not apply the iOS icon mask."""
    size = img.size[0]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255
    )
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img.convert("RGB"), (0, 0), mask)
    return out


def load_font(size):
    """The macOS system font, falling back rather than failing the whole run.

    The fallback is a real risk to the output, not just a smaller font: PIL's default
    is a fixed-size bitmap face, so it ignores `size` and cannot draw Cyrillic. On a
    machine without these faces the OG image renders as tofu at the wrong scale. It
    still succeeds, which is why this is worth saying out loud.
    """
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
    plain = Image.open(SOURCE_PLAIN).convert("RGB") if SOURCE_PLAIN.exists() else src

    # At 16 px the mark is about eight distinguishable pixels across. The wordmark on
    # the screen is illegible there, so 16 and 32 come from the plain variant; 48 is
    # large enough to hold it.
    for px in (16, 32, 48):
        source = src if px >= 48 else plain
        source.resize((px, px), Image.LANCZOS).save(PUBLIC / f"favicon-{px}x{px}.png")

    rounded(src, 0.23).resize((180, 180), Image.LANCZOS).save(
        PUBLIC / "apple-touch-icon.png"
    )

    # A three-size .ico for older browsers, which read this instead of the PNGs.
    plain.resize((48, 48), Image.LANCZOS).save(
        PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)]
    )

    # OG: 1200x630, mark left, text right. Nothing fine-grained — feeds resample this
    # down to roughly 300 px wide.
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
