# Art Asset Licenses

## Auth Poster Mosaic

The animated poster mosaic in `AnimatedPosterMosaic.swift` loads images
from public CDN URLs at runtime. These are NOT bundled in the app binary.

### Source: TMDB (The Movie Database)

- **URL pattern:** `https://image.tmdb.org/t/p/w500/<path>.jpg`
- **License:** TMDB API terms — images are provided for display purposes
  under their API license. No artwork is copied, redistributed or
  bundled in the app.
- **Usage:** Runtime `AsyncImage` fetch only. No local caching beyond
  standard URLCache. No metadata extraction.

### Movies referenced (as of 2026-07-12):

| Movie | TMDB Path |
|---|---|
| Dune | `8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg` |
| Oppenheimer | `qNBAXBIQlnOThrVvA6mA2B5ggV6.jpg` |
| Barbie | `1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg` |
| Joker | `aDQZHvI3rGdtzZ2nFGzJXWL7X5m.jpg` |
| Interstellar | `8Gxv8gSFCU0XGDykEGv7clRv7wq.jpg` |
| Shutter Island | `kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg` |
| Blade Runner 2049 | `9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg` |
| The Dark Knight | `b41qXmtBtZQ3hU2rL3mJ8mFnFk.jpg` |
| Inception | `7Hfi13FfRTIfEYFiQXiIuV2xV8a.jpg` |

### Compliance

- No Pinterest art, anime illustrations, or proprietary streaming
  service branding is used.
- No EXIF or location metadata is stored.
- Images are loaded on-demand and subject to user's network.
- If TMDB is unavailable, fallback shows `Cinema2026.surface` rectangles.

### Future: Bundled Assets

For offline support and guaranteed availability, replace runtime CDN
fetches with bundled licensed PNGs:

```
Assets.xcassets/AuthPoster01.imageset ... AuthPoster09.imageset
```

Each bundled asset must have:
- Original source documented
- Artist/photographer credited
- License type (CC-BY, licensed, original)
- Territory restrictions
- Expiry date (if applicable)
