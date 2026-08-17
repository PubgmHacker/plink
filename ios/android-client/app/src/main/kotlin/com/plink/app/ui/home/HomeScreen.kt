package com.plink.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.plink.app.R
import com.plink.app.data.models.Room
import com.plink.app.data.models.TrendingVideo
import com.plink.app.viewmodel.HomeViewModel
import kotlinx.coroutines.delay

// Hero banner kinds
enum class HeroBanner(val resId: Int, val title: String, val subtitle: String, val accentColor: Color) {
    WATCH_TOGETHER(R.raw.hero_banner_watch_together, "Смотрим вместе", "Watch together. Anywhere. Together.", Color(0xFF2DE2E6)),
    AI_COMPANION(R.raw.hero_banner_ai_companion, "AI Companion", "Умный помощник для совместного просмотра", Color(0xFF26D9A4)),
    SYNC_DEVICES(R.raw.hero_banner_sync_devices, "Синхронный просмотр", "Sync ±2s across iOS, Android, Mac, Windows", Color(0xFF0EB5C9))
}

@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onOpenRoom: (Room) -> Unit,
    onOpenProfile: () -> Unit,
) {
    val state by viewModel.state.collectAsState()

    if (state.loading) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator()
            Text("Загрузка...")
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Plink", style = MaterialTheme.typography.headlineMedium)
                TextButton(onClick = onOpenProfile) { Text("Профиль") }
            }
        }

        // Hero video carousel
        item { HeroVideoCarousel() }

        state.error?.let { error ->
            item {
                Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp))
            }
        }

        item {
            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                Text("Популярное", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.trending) { video ->
                        TrendingCard(
                            video = video,
                            enabled = !state.actionLoading,
                            onClick = { viewModel.createFromVideo(video, onOpenRoom) },
                        )
                    }
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                Text("Войти по коду", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = state.joinCode,
                        onValueChange = viewModel::setJoinCode,
                        placeholder = { Text("ABCD12") },
                        modifier = Modifier.weight(1f),
                    )
                    Button(onClick = { viewModel.joinByCode(onOpenRoom) }) {
                        Text("Войти")
                    }
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                Text("Комнаты", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.rooms.forEach { room ->
                        RoomCard(room = room, onClick = { onOpenRoom(room) })
                    }
                }
            }
        }
    }
}

@Composable
private fun HeroVideoCarousel() {
    val banners = HeroBanner.values().toList()
    var currentIndex by remember { mutableStateOf(0) }

    // Auto-scroll every 6 seconds
    LaunchedEffect(Unit) {
        while (true) {
            delay(6000)
            currentIndex = (currentIndex + 1) % banners.size
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp)
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(Color.Black)
    ) {
        HeroVideoBannerView(banner = banners[currentIndex])

        // Gradient overlay
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color(0xE60E1113)
                        ),
                        startY = 300f,
                        endY = 800f
                    )
                )
        )

        // Text overlay
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(20.dp)
        ) {
            Text(
                text = banners[currentIndex].title,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = banners[currentIndex].subtitle,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = banners[currentIndex].accentColor
            )
            // Dots indicator
            Row(
                modifier = Modifier.padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                banners.forEachIndexed { index, _ ->
                    Box(
                        modifier = Modifier
                            .size(if (index == currentIndex) 8.dp else 6.dp)
                            .clip(RoundedCornerShape(50))
                            .background(
                                if (index == currentIndex) banners[currentIndex].accentColor
                                else Color.White.copy(alpha = 0.4f)
                            )
                    )
                }
            }
        }
    }
}

@Composable
private fun HeroVideoBannerView(banner: HeroBanner) {
    val context = LocalContext.current
    val player = remember {
        ExoPlayer.Builder(context).build().apply {
            val uri = "android.resource://${context.packageName}/${banner.resId}"
            setMediaItem(MediaItem.fromUri(uri))
            repeatMode = Player.REPEAT_MODE_ONE
            playWhenReady = true
            volume = 0f
            prepare()
        }
    }
    DisposableEffect(Unit) {
        onDispose { player.release() }
    }
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                this.player = player
                useController = false
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
            }
        },
        modifier = Modifier.fillMaxSize()
    )
}

@Composable
private fun TrendingCard(
    video: TrendingVideo,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .size(width = 160.dp, height = 220.dp)
            .clickable(enabled = enabled, onClick = onClick)
    ) {
        Column {
            AsyncImage(
                model = video.thumbnailURL,
                contentDescription = video.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
            )
            Column(modifier = Modifier.padding(8.dp)) {
                Text(
                    video.title,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun RoomCard(room: Room, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(room.name, style = MaterialTheme.typography.titleSmall)
            Text("Код: ${room.code}", style = MaterialTheme.typography.bodySmall)
        }
    }
}
