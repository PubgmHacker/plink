package com.plink.app.ui.room

object YouTubePlayerHtml {
    private const val ORIGIN = "https://plink-backend-production-ef31.up.railway.app"

    /** Backend-hosted player (needs Railway deploy of PlinkNative bridge). */
    fun hostedPlayerUrl(videoId: String): String {
        val safeId = videoId.filter { it.isLetterOrDigit() || it == '_' || it == '-' }
        return "$ORIGIN/api/media/youtube-player?id=$safeId"
    }

    /**
     * Self-contained IFrame API page with:
     * - real origin via loadDataWithBaseURL(BASE_URL) (avoids YT 153)
     * - window.plinkCmd for host/sync control
     * - PlinkNative.onEvent for Android JavascriptInterface
     */
    fun build(videoId: String): String {
        val safeId = videoId.filter { it.isLetterOrDigit() || it == '_' || it == '-' }
        require(safeId.length in 6..20) { "Invalid YouTube id" }
        return """
            <!doctype html>
            <html>
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
                <style>
                  html,body,#player{margin:0;padding:0;width:100%;height:100%;background:#0E1016;overflow:hidden}
                  iframe{width:100%!important;height:100%!important;border:0}
                </style>
              </head>
              <body>
                <div id="player"></div>
                <script>
                  var tag = document.createElement('script');
                  tag.src = 'https://www.youtube.com/iframe_api';
                  document.head.appendChild(tag);

                  var player = null;
                  var ready = false;
                  var videoId = '$safeId';

                  function post(type, payload) {
                    var msg = Object.assign({ source: 'plink-yt', type: type }, payload || {});
                    try {
                      if (window.PlinkNative && typeof window.PlinkNative.onEvent === 'function') {
                        window.PlinkNative.onEvent(JSON.stringify(msg));
                      }
                    } catch (e) {}
                  }

                  function snapshot() {
                    if (!player || !ready) return { time: 0, duration: 0, state: -1, playing: false };
                    var state = player.getPlayerState ? player.getPlayerState() : -1;
                    return {
                      time: (player.getCurrentTime && player.getCurrentTime()) || 0,
                      duration: (player.getDuration && player.getDuration()) || 0,
                      state: state,
                      playing: state === 1
                    };
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
                    runCmd(Object.assign({ target: 'plink-yt', cmd: cmd }, extra || {}));
                  };

                  function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                      height: '100%',
                      width: '100%',
                      videoId: videoId,
                      playerVars: {
                        playsinline: 1,
                        controls: 1,
                        modestbranding: 1,
                        rel: 0,
                        iv_load_policy: 3,
                        enablejsapi: 1,
                        origin: '$ORIGIN',
                        widget_referrer: '$ORIGIN',
                        autoplay: 1
                      },
                      events: {
                        onReady: function() {
                          ready = true;
                          try { player.mute(); player.playVideo(); } catch (e) {}
                          setTimeout(function() { try { player.unMute(); } catch (e) {} }, 800);
                          post('ready', snapshot());
                        },
                        onStateChange: function(e) {
                          post('state', Object.assign({ ytState: e.data }, snapshot()));
                        },
                        onError: function(e) {
                          post('error', { code: e.data });
                        }
                      }
                    });
                  }

                  setInterval(function() {
                    if (ready) post('tick', snapshot());
                  }, 500);
                </script>
              </body>
            </html>
        """.trimIndent()
    }

    const val BASE_URL = "$ORIGIN/"
}
