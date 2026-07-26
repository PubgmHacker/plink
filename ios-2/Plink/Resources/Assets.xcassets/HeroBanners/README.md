# Plink Hero Banners

## 2 готовых баннера (от Grok Imagine):

### Banner 1: "Смотрим вместе" (Watch Together)
- **Описание:** 3 силуэта друзей на диване перед светящимся teal-green экраном с вихрем
- **Использование:** Hero на главной странице, экран входа, App Store screenshots

### Banner 2: "AI Companion"
- **Описание:** Центральный светящийся cyan-emerald AI orb + 7-8 карточек с людьми на орбите
- **Использование:** Hero на главной странице, AI Companion промо, Plink+ страница

## Файлы по платформам:

### iOS (`Plink/Resources/Assets.xcassets/HeroBanners/`)
```
HeroBanners/
├── Contents.json
├── hero_banner_watch_together.imageset/
│   ├── Contents.json
│   ├── hero_banner_watch_together.mp4         (1920×1080, 1.5 MB)
│   └── hero_banner_watch_together_poster.png  (1920×1080, 847 KB)
└── hero_banner_ai_companion.imageset/
    ├── Contents.json
    ├── hero_banner_ai_companion.mp4           (1920×1080, 2.2 MB)
    └── hero_banner_ai_companion_poster.png    (1920×1080, 897 KB)
```

Также в `Plink/Resources/Banners/` — копии для прямого доступа через `Bundle.main.url()`.

### Android (`android-client/app/src/main/res/`)
```
res/
├── raw/                                              # MP4 видео
│   ├── hero_banner_watch_together.mp4               (1920×1080)
│   ├── hero_banner_watch_together_vertical.mp4      (1080×1920)
│   ├── hero_banner_ai_companion.mp4                 (1920×1080)
│   └── hero_banner_ai_companion_vertical.mp4        (1080×1920)
└── drawable/                                         # PNG постеры
    ├── hero_banner_watch_together_poster.png
    └── hero_banner_ai_companion_poster.png
```

### Desktop (`windows-client/public/banners/`)
```
banners/
├── hero_banner_watch_together.mp4           (1920×1080 H.264)
├── hero_banner_watch_together_vertical.mp4  (1080×1920 H.264)
├── hero_banner_watch_together.webm          (VP9, 215 KB)
├── hero_banner_watch_together_poster.png    (1920×1080)
├── hero_banner_ai_companion.mp4             (1920×1080 H.264)
├── hero_banner_ai_companion_vertical.mp4    (1080×1920 H.264)
├── hero_banner_ai_companion.webm            (VP9, 202 KB)
└── hero_banner_ai_companion_poster.png      (1920×1080)
```

### Landing (`plink-landing/public/banners/`)
```
banners/
├── hero_banner_watch_together.mp4           (16:9 для hero section)
├── hero_banner_watch_together_poster.png
├── hero_banner_ai_companion.mp4
└── hero_banner_ai_companion_poster.png
```

## Характеристики:

| Параметр | Banner 1 | Banner 2 |
|----------|----------|----------|
| Разрешение | 1920×1080 | 1920×1080 |
| Длительность | 6 сек | 6 сек |
| FPS | 24 | 24 |
| Кодек | H.264 | H.264 |
| Размер MP4 | 1.5 MB | 2.2 MB |
| Размер WebM | 215 KB | 202 KB |
| Loop | Да (muted) | Да (muted) |

## Использование в коде:

### iOS (SwiftUI)
```swift
import AVKit
import SwiftUI

struct HeroVideoBanner: View {
    private let player: AVPlayer = {
        guard let url = Bundle.main.url(forResource: "hero_banner_watch_together", withExtension: "mp4") else {
            return AVPlayer()
        }
        let p = AVPlayer(url: url)
        p.actionAtItemEnd = .none
        p.isMuted = true
        return p
    }()

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16/9, contentMode: .fill)
            .frame(height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .onAppear {
                player.play()
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem, queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Смотрим вместе")
                        .font(.system(size: 32, weight: .800))
                        .foregroundStyle(.white)
                    Text("Watch together. Anywhere. Together.")
                        .font(.system(size: 14, weight: .600))
                        .foregroundStyle(Color(hex: 0x2DE2E6))
                }
                .padding(28)
                .shadow(radius: 8)
            }
    }
}
```

### Android (Jetpack Compose)
```kotlin
import android.net.Uri
import androidx.compose.runtime.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.media3.ui.PlayerView
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.Player

@Composable
fun HeroVideoBanner(bannerResId: Int = R.raw.hero_banner_watch_together) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val player = remember {
        ExoPlayer.Builder(context).build().apply {
            val uri = "android.resource://${context.packageName}/$bannerResId"
            setMediaItem(MediaItem.fromUri(uri))
            repeatMode = Player.REPEAT_MODE_ONE
            playWhenReady = true
            volume = 0f
            prepare()
        }
    }
    DisposableEffect(Unit) { onDispose { player.release() } }
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                this.player = player
                useController = false
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(16f / 9f)
            .clip(RoundedCornerShape(20.dp))
    )
}
```

### Desktop (React + Tauri)
```tsx
export function HeroVideoBanner({ banner = 'watch_together' }) {
  return (
    <video
      autoPlay loop muted playsInline
      poster={`/banners/hero_banner_${banner}_poster.png`}
      style={{ width: '100%', borderRadius: 20, objectFit: 'cover' }}
    >
      <source src={`/banners/hero_banner_${banner}.mp4`} type="video/mp4" />
      <source src={`/banners/hero_banner_${banner}.webm`} type="video/webm" />
    </video>
  );
}
```

## Источники:
- **Banner 1:** `grok-video-e96ef2ab-4468-4cc5-8a5c-d910ecb7b09f.mp4` (Grok Imagine)
- **Banner 2:** `grok-video-95f0d48e-b5ca-4f07-9dff-3d5882094669.mp4` (Grok Imagine)

## Цвета (Plink Cinema2026):
- Background: `#0E1113` (обсидиан)
- Accent 1: `#2DE2E6` (bio-cyan)
- Accent 2: `#26D9A4` (bio-emerald)
- Text: `#ECEBEA` (warm white)
