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

Icons generated from source SVG. For raster exports, use `ios-2/scripts/make_app_icons.py` or `landing/scripts/make_brand_assets.py`.
