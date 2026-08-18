// v22: reliable YT IFrame boot on WKWebView + iOS bridge.
// Hosted at GET /api/media/youtube-player?id=VIDEO_ID — real HTTPS origin (no YT 153).
//
// iOS EmbeddedPlaybackController contract:
//   - window.webkit.messageHandlers.plinkPlayer.postMessage({ event, ... })
//   - window.plinkPlay / plinkPause / plinkSeek / plinkSnapshot
//   - window.__plinkIsReady() → boolean

// «свой полноценный плеер».
// `chrome` управляет тем, кто рисует контролы:
//   'plink' (по умолчанию) → controls:0, всю панель рисует приложение;
//   'youtube'              → controls:1, прежнее поведение (запасной путь).
// Плюс расширенный JS-API: скорость, качество, громкость и буферизация —
// без них своя панель управления невозможна.
export function youtubePlayerHTML(videoId: string, chrome: 'plink' | 'youtube' = 'plink'): string {
  const safeId = String(videoId).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 20);
  const showNativeControls = chrome === 'youtube' ? 1 : 0;

  return `<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; script-src * 'unsafe-inline' 'unsafe-eval'; style-src * 'unsafe-inline'; img-src * data: blob:; media-src *; connect-src * wss:; frame-src *; child-src *;">
    <style>
        body, html { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #0E1016; }
        #player { width: 100%; height: 100%; }
        iframe { width: 100% !important; height: 100% !important; border: 0; }
    </style>
</head>
<body>
    <div id="player"></div>
    <script>
        var player = null;
        var ready = false;
        var playerBooted = false;
        var videoId = ${JSON.stringify(safeId)};

        function snapshot() {
            if (!player || !ready) {
                return { time: 0, duration: 0, state: -1, playing: false,
                         buffered: 0, rate: 1, muted: false, volume: 100,
                         quality: '', qualities: [] };
            }
            var state = player.getPlayerState ? player.getPlayerState() : -1;
            var loaded = 0;
            try { loaded = player.getVideoLoadedFraction ? player.getVideoLoadedFraction() : 0; } catch (e) {}
            var rate = 1;
            try { rate = player.getPlaybackRate ? player.getPlaybackRate() : 1; } catch (e) {}
            var muted = false;
            try { muted = player.isMuted ? player.isMuted() : false; } catch (e) {}
            var volume = 100;
            try { volume = player.getVolume ? player.getVolume() : 100; } catch (e) {}
            var quality = '';
            try { quality = player.getPlaybackQuality ? player.getPlaybackQuality() : ''; } catch (e) {}
            var qualities = [];
            try { qualities = player.getAvailableQualityLevels ? player.getAvailableQualityLevels() : []; } catch (e) {}
            return {
                time: (player.getCurrentTime && player.getCurrentTime()) || 0,
                duration: (player.getDuration && player.getDuration()) || 0,
                state: state,
                playing: state === 1,
                // Всё нужное для своей панели управления — одним вызовом,
                // чтобы не гонять по мосту пять отдельных запросов на каждый тик.
                buffered: loaded,
                rate: rate,
                muted: muted,
                volume: volume,
                quality: quality,
                qualities: qualities
            };
        }

        // Unified event fan-out for iOS / Android / desktop.
        // iOS expects: { event: 'ready'|'state'|'error', state?, code? }
        function post(type, payload) {
            payload = payload || {};

            // 1) iOS WKWebView — EmbeddedPlaybackController bridge
            try {
                if (window.webkit
                    && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.plinkPlayer) {
                    var iosMsg = { event: type };
                    if (type === 'state') {
                        var st = payload.state;
                        if (st === undefined) st = payload.ytState;
                        if (typeof st === 'number') iosMsg.state = st;
                    }
                    if (type === 'error' && payload.code !== undefined) {
                        iosMsg.code = payload.code;
                    }
                    window.webkit.messageHandlers.plinkPlayer.postMessage(iosMsg);
                }
            } catch (e) {}

            // 2) Android PlinkNative
            var msg = Object.assign({ source: 'plink-yt', type: type }, payload);
            try {
                if (window.PlinkNative && typeof window.PlinkNative.onEvent === 'function') {
                    window.PlinkNative.onEvent(JSON.stringify(msg));
                }
            } catch (e) {}

            // 3) Desktop iframe parent
            try {
                if (window.parent && window.parent !== window) {
                    window.parent.postMessage(msg, '*');
                }
            } catch (e) {}

            // 4) Optional JS hook
            try {
                if (typeof window.__plinkOnEvent === 'function') {
                    window.__plinkOnEvent(type, msg);
                }
            } catch (e) {}
        }

        function runCmd(data) {
            if (!data || !player || !ready) return;
            try {
                switch (data.cmd) {
                    case 'play': player.playVideo(); break;
                    case 'pause': player.pauseVideo(); break;
                    case 'seek':
                        if (typeof data.seconds === 'number') player.seekTo(data.seconds, true);
                        break;
                    case 'load':
                        if (typeof data.videoId === 'string' && data.videoId.length >= 6) {
                            videoId = data.videoId;
                            player.loadVideoById(videoId);
                        }
                        break;
                    case 'mute': player.mute(); break;
                    case 'unmute': player.unMute(); break;
                    case 'getState': post('snapshot', snapshot()); break;
                    default: break;
                }
            } catch (e) {
                post('error', { code: -1, message: String(e && e.message || e) });
            }
        }

        window.plinkCmd = function(cmd, extra) {
            var data = Object.assign({ target: 'plink-yt', cmd: cmd }, extra || {});
            runCmd(data);
        };

        window.plinkPlay = function() {
            if (player && ready && player.playVideo) { player.playVideo(); return true; }
            return false;
        };
        window.plinkPause = function() {
            if (player && ready && player.pauseVideo) { player.pauseVideo(); return true; }
            return false;
        };
        window.plinkSeek = function(seconds) {
            if (player && ready && player.seekTo) {
                player.seekTo(seconds, true);
                return true;
            }
            return false;
        };
        window.plinkSnapshot = function() {
            return snapshot();
        };
        window.__plinkIsReady = function() { return !!ready; };

        // ── API для своей панели управления (M40) ──────────────────────────
        window.plinkSetRate = function(rate) {
            if (player && ready && player.setPlaybackRate) {
                player.setPlaybackRate(rate);
                return true;
            }
            return false;
        };
        window.plinkSetQuality = function(q) {
            // setPlaybackQuality — «пожелание»: YouTube может его не выполнить,
            // поэтому реальное качество всегда читаем обратно из snapshot().
            if (player && ready && player.setPlaybackQuality) {
                player.setPlaybackQuality(q);
                return true;
            }
            return false;
        };
        window.plinkSetVolume = function(v) {
            if (player && ready && player.setVolume) {
                player.setVolume(Math.max(0, Math.min(100, v)));
                return true;
            }
            return false;
        };
        window.plinkSetMuted = function(m) {
            if (!player || !ready) return false;
            try { m ? player.mute() : player.unMute(); return true; } catch (e) { return false; }
        };

        function bootPlayer() {
            if (playerBooted) return;
            if (!(window.YT && window.YT.Player)) return;
            playerBooted = true;
            try {
                player = new YT.Player('player', {
                    height: '100%',
                    width: '100%',
                    videoId: videoId,
                    host: 'https://www.youtube.com',
                    playerVars: {
                        playsinline: 1,
                        // 0 = свою панель рисует Plink, 1 = родные контролы YouTube
                        controls: ${showNativeControls},
                        // При своей панели прячем лишние наложения YouTube,
                        // иначе они перехватывают тапы у нашего seek-бара.
                        disablekb: ${showNativeControls === 0 ? 1 : 0},
                        rel: 0,
                        modestbranding: 1,
                        iv_load_policy: 3,
                        enablejsapi: 1,
                        origin: window.location.origin,
                        autoplay: 1,
                        fs: 1
                    },
                    events: {
                        onReady: function() {
                            ready = true;
                            // Restore the caller's mute state rather than assuming
                            // unmuted: autoplay requires a muted start, and racing
                            // that with a user unmute leaves playback stuck muted.
                            try {
                                var wasMuted = player.isMuted ? player.isMuted() : false;
                                player.mute(); player.playVideo();
                                setTimeout(function() {
                                    try {
                                        if (!wasMuted) player.unMute();
                                    } catch (e) {}
                                }, 1200);  // longer = safer on slow WKWebView first paint
                            } catch (e) {}
                            // M29-YT: state-3 recovery at t+3s (unstick buffering)
                            setTimeout(function() {
                                try {
                                    if (player && player.getPlayerState && player.getPlayerState() === 3) {
                                        var t = player.getCurrentTime ? player.getCurrentTime() : 0;
                                        player.seekTo(t, true);
                                    }
                                } catch (e) {}
                            }, 3000);
                            post('ready', snapshot());
                        },
                        onStateChange: function(event) {
                            // State means player is live even if onReady was missed
                            if (!ready) {
                                ready = true;
                                post('ready', snapshot());
                            }
                            post('state', Object.assign({ state: event.data, ytState: event.data }, snapshot()));
                        },
                        onError: function(event) {
                            post('error', { code: event.data });
                        }
                    }
                });
            } catch (e) {
                playerBooted = false;
                post('error', { code: -2, message: String(e && e.message || e) });
            }
        }

        // MUST be on window — YT IFrame API looks up global by name.
        // If the script is already cached, call immediately.
        window.onYouTubeIframeAPIReady = function() {
            bootPlayer();
        };

        // Fallback: API already present or callback was missed (common on WKWebView cache).
        (function waitForYT() {
            if (window.YT && window.YT.Player) {
                bootPlayer();
                return;
            }
            var tries = 0;
            var t = setInterval(function() {
                tries++;
                if (window.YT && window.YT.Player) {
                    clearInterval(t);
                    bootPlayer();
                } else if (tries > 100) {
                    clearInterval(t);
                }
            }, 100);
        })();

        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        tag.async = true;
        document.head.appendChild(tag);

        window.addEventListener('message', function(event) {
            var data = event.data;
            if (!data || data.target !== 'plink-yt') return;
            runCmd(data);
        });

        setInterval(function() {
            if (ready) post('tick', snapshot());
        }, 500);
    </script>
</body>
</html>`;
}
