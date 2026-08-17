package com.plink.app.ui.room

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.plink.app.viewmodel.RoomViewModel
import org.json.JSONObject

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun RoomScreen(
    viewModel: RoomViewModel,
    userId: String,
    onLeave: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val listState = rememberLazyListState()
    val webViewRef = remember { arrayOfNulls<WebView>(1) }

    BackHandler { onLeave() }

    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.lastIndex)
        }
    }

    // Apply player commands from ViewModel (sync / host controls)
    LaunchedEffect(state.playerCommand?.id) {
        val cmd = state.playerCommand ?: return@LaunchedEffect
        val wv = webViewRef[0] ?: return@LaunchedEffect
        val js = when (cmd.cmd) {
            "play" -> "window.plinkCmd && window.plinkCmd('play');"
            "pause" -> "window.plinkCmd && window.plinkCmd('pause');"
            "seek" -> {
                val sec = cmd.seconds ?: 0.0
                "window.plinkCmd && window.plinkCmd('seek', {seconds: $sec});"
            }
            else -> return@LaunchedEffect
        }
        wv.evaluateJavascript(js, null)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(onClick = onLeave) { Text("← Назад") }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(state.room.name, style = MaterialTheme.typography.titleSmall)
                Text(
                    "Код: ${state.room.code} · ${if (state.role == "host") "Host" else "Guest"}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    if (state.connected) "Synced" else "…",
                    color = if (state.connected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    },
                )
                if (kotlin.math.abs(state.driftMs) > 50) {
                    Text(
                        "${state.driftMs.toInt()}ms",
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }

        state.error?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
        }

        val videoId = state.room.mediaItem?.videoId
        val streamUrl = state.room.mediaItem?.streamURL
        val isYouTube = !videoId.isNullOrBlank() && videoId.length in 6..20

        if (isYouTube || !streamUrl.isNullOrBlank()) {
            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp),
                factory = { context ->
                    WebView(context).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        webChromeClient = WebChromeClient()
                        val mainHandler = Handler(Looper.getMainLooper())
                        addJavascriptInterface(
                            PlinkNativeBridge(
                                onReady = { mainHandler.post { viewModel.onPlayerReady() } },
                                onTick = { t, d, p ->
                                    mainHandler.post { viewModel.onPlayerTick(t, d, p) }
                                },
                                onError = { code ->
                                    mainHandler.post { viewModel.onPlayerError(code) }
                                },
                            ),
                            "PlinkNative",
                        )
                        webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView?, url: String?) {
                                super.onPageFinished(view, url)
                                // Nudge ready if already playing
                                view?.evaluateJavascript(
                                    "if(window.plinkCmd){window.plinkCmd('getState');}",
                                    null,
                                )
                            }
                        }
                        webViewRef[0] = this
                        if (isYouTube) {
                            // Local HTML + Railway origin base → no 153, full JS bridge for sync
                            loadDataWithBaseURL(
                                YouTubePlayerHtml.BASE_URL,
                                YouTubePlayerHtml.build(videoId!!),
                                "text/html",
                                "UTF-8",
                                null,
                            )
                        } else {
                            loadUrl(streamUrl!!)
                        }
                    }
                },
                update = { webView ->
                    webViewRef[0] = webView
                    // Don't reload YouTube HTML on every recomposition — bridge would reset
                    if (!isYouTube && streamUrl != null && webView.url != streamUrl) {
                        webView.loadUrl(streamUrl)
                    }
                },
            )
        } else {
            Text(
                "Видео не выбрано",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
            )
        }

        if (state.role == "host" && isYouTube) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(onClick = { viewModel.hostSeekBy(-10.0) }) { Text("−10s") }
                TextButton(onClick = viewModel::hostPlayPause) {
                    Text(if (state.playing) "Pause" else "Play")
                }
                TextButton(onClick = { viewModel.hostSeekBy(10.0) }) { Text("+10s") }
                Text(
                    formatTime(state.positionSec) + " / " + formatTime(state.durationSec),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
            }
        }

        if (state.participants.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.participants.forEach { participant ->
                    Text(participant.username, style = MaterialTheme.typography.labelSmall)
                }
            }
        }

        Text(
            "Чат",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        )

        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(state.messages, key = { it.id }) { message ->
                val mine = message.senderID == userId
                Text(
                    text = message.text,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(8.dp),
                    color = if (mine) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = state.draft,
                onValueChange = viewModel::setDraft,
                placeholder = { Text("Сообщение...") },
                modifier = Modifier.weight(1f),
                singleLine = true,
            )
            Button(onClick = viewModel::sendMessage) { Text("→") }
        }
    }
}

private fun formatTime(sec: Double): String {
    if (!sec.isFinite() || sec < 0) return "0:00"
    val m = (sec / 60).toInt()
    val s = (sec % 60).toInt()
    return "$m:${s.toString().padStart(2, '0')}"
}

/** Bridge for hosted YouTube player (window.PlinkNative.onEvent). */
private class PlinkNativeBridge(
    private val onReady: () -> Unit,
    private val onTick: (time: Double, duration: Double, playing: Boolean) -> Unit,
    private val onError: (code: Int) -> Unit,
) {
    @JavascriptInterface
    fun onEvent(json: String) {
        try {
            val obj = JSONObject(json)
            when (obj.optString("type")) {
                "ready" -> onReady()
                "tick", "state", "snapshot" -> {
                    onTick(
                        obj.optDouble("time", 0.0),
                        obj.optDouble("duration", 0.0),
                        obj.optBoolean("playing", false),
                    )
                }
                "error" -> onError(obj.optInt("code", -1))
            }
        } catch (_: Exception) {
        }
    }
}
