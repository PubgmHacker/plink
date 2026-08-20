# Plink — Brand Logo System

Unified logo system for Plink (Плинк) — watch together, frame in frame.

## Files

| File | Usage | Size |
|------|-------|------|
| `logo-horizontal.svg` | Primary lockup: icon + wordmark (websites, presentations, social) | 400×120 |
| `logo-stacked.svg` | Vertical lockup: icon above wordmark (app store, splash) | 300×360 |
| `logo-icon-only.svg` | Standalone icon (favicon, app icon source) | 512×512 |
| `logo-light-bg.svg` | Horizontal lockup for light/white backgrounds | 400×120 |
| `wordmark.svg` | Text-only PLINK (watermarks, minimal) | 320×80 |
| `mark-play.svg` | Simplified play mark (website nav, favicon) | 120×120 |

## Brand Colors

| Name | Hex | Usage |
|------|-----|-------|
| **Graphite Lift** | `#3A3C42` | Icon body top |
| **Graphite Deep** | `#16171B` | Icon body bottom |
| **Ink** | `#08090B` | Silhouettes, letterbox, couch |
| **Warm** | `#FFD694` | Screen glow — **the** brand constant |
| **Warm Hot** | `#FFF0D6` | Screen center, text gradient top |
| **Teal** | `#19E0C0` | Accent (sync, progress, active) |
| **Violet** | `#7C5CFF` | Secondary accent |
| **Amber** | `#F5C26B` | Stamps, badges, errors |

## Typography

- **Display / Wordmark:** Playfair Display, italic, Black (900)
- **Body:** Inter, 300–700
- **Mono:** System UI monospace (codes, stamps)

## Logo Anatomy

The icon depicts two viewers sitting on a couch, watching a letterboxed film on a glowing screen. The warm screen light is the only color in the brand mark — universal across all themes (Aurora, Cosmos, Magma, Verdant, Ember, Violet).

**Key proportions (must match across all representations):**
- Screen: 54% width × 31% height of icon
- Letterbox bars: calculated from 2.35:1 aspect ratio
- Silhouettes: head = circle, shoulders = rounded rectangle
- Couch: single dense bar, does not reach edges

## Usage Rules

1. **Minimum size:** 24×24 px (icon), 80×24 px (horizontal)
2. **Clear space:** 1× icon width on all sides
3. **Don't:** rotate, stretch, add shadows beyond spec, change colors
4. **Dark backgrounds:** use `logo-horizontal.svg` or `logo-icon-only.svg`
5. **Light backgrounds:** use `logo-light-bg.svg`

## Generation

There is no single build step that turns the SVGs in this directory into the shipped
icon, and it is worth knowing the real chain before editing anything:

1. [`ios/scripts/make_app_icons.py`](../ios/scripts/make_app_icons.py) is the
   **geometric source of truth.** It draws the mark with PIL rather than reading an
   SVG, and renders three candidate directions at 1024/180/120/60 px into
   `/tmp/plink-icons` — it is a design tool, not part of any build, which is why its
   output goes to a scratch directory. `PlinkBrandMark.swift` (the in-app SwiftUI
   mark) states outright that its proportions are taken from this script, so the two
   must be changed together or the icon and the launch screen stop matching.
2. The chosen direction is copied by hand to
   `ios/Plink/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. That
   file, not anything in this directory, is what ships on the home screen.
3. [`landing/scripts/make_brand_assets.py`](../landing/scripts/make_brand_assets.py)
   reads that shipped app icon and derives `landing/public/` — favicons, the
   apple-touch icon, `og-image.png`. Below roughly 32 px it switches to
   `plink-icon-plain-1024.png` from this directory instead, because the word PLINK on
   the screen turns to mud at that size and smears the pool of light the mark depends
   on.

So `plink-icon-1024.png` here is an export for documents and decks; it is **not**
byte-identical to the shipped app icon and is not the source of it. Change the icon in
step 1, re-copy in step 2, then re-run step 3.

## Design references

The two owner-supplied layout references this direction was drawn against live in
[`docs/design/references/`](../docs/design/references/) — the desktop
(MacBook + Windows) framing and the auth-window banner. `PLINK_DESIGN_DIRECTION.md` at
the repository root is the written half of the same thing.

## Explorations

[`explorations/`](explorations/) holds two superseded logo rounds, kept because the
reasoning in them is still useful and the alternatives get re-proposed otherwise:

| Round | Concepts | Outcome |
|-------|----------|---------|
| [`round-2/`](explorations/round-2/) | duo-play, sync-rings, film-play | Not adopted |
| [`round-3/`](explorations/round-3/) | wave-play (Spotify-like), two-screens, plex-p | Not adopted |

Each round has a `preview.html` — open it in a browser rather than reading the SVGs.
Round 3's page also lays the concepts against the competitor icons they were judged
next to. **Nothing under `explorations/` ships.** The live system is the six SVGs
listed above; if you are looking for an asset to use, it is one of those.

