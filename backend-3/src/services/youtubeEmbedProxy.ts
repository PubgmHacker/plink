// GET /api/media/youtube-embed?id=VIDEO_ID — Full Embed Page Proxy (v12)
//
// v12 approach: backend fetches the ENTIRE youtube.com/embed/ page,
// rewrites relative URLs to absolute, and serves it to iOS WKWebView.
//
// Why this works where v11 failed:
//   v11: our HTML → IFrame API creates iframe to youtube.com → WKWebView
//        loads iframe → YouTube bot-checks the iframe request → "Sign in"
//   v12: backend fetches embed page from YouTube (Railway IP) → serves
//        HTML to WKWebView → player JS runs directly in the page → NO
//        iframe request from WKWebView → NO bot check
//
// The only youtube.com requests from WKWebView are static JS/CSS files
// (player JS, CSS) which YouTube doesn't bot-check. Video data comes from
// googlevideo.com CDN (also not bot-checked).

// v12.1: inject window.safari shim + other WKWebView detection bypasses
// YouTube's player JS checks window.safari (exists in Safari, NOT in WKWebView).
// Without this shim, YouTube detects WKWebView → error 153.
const SAFARI_SHIM = `<script>
// Shim: make WKWebView look like Safari to YouTube's player JS
window.safari = {
  pushNotification: {
    toString: function() { return '[object SafariRemoteNotification]'; },
    permission: function() { return 'default'; },
    requestPermission: function() {},
  }
};
// navigator.vendor: Safari reports 'Apple Computer, Inc.', WKWebView reports ''
try { Object.defineProperty(navigator, 'vendor', { get: function() { return 'Apple Computer, Inc.'; } }); } catch(e) {}
// navigator.platform: ensure 'iPhone' (WKWebView might report differently)
try { Object.defineProperty(navigator, 'platform', { get: function() { return 'iPhone'; } }); } catch(e) {}
// navigator.maxTouchPoints: Safari on iPhone = 5, WKWebView might report 0
try { Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 5; } }); } catch(e) {}
// Remove window.webkit.messageHandlers if empty (WKWebView gives empty object, Safari has none)
try { if (window.webkit && window.webkit.messageHandlers && Object.keys(window.webkit.messageHandlers).length === 0) { delete window.webkit.messageHandlers; } } catch(e) {}
</script>`;

export async function proxyYouTubeEmbed(videoId: string): Promise<string> {
  const embedUrl = `https://www.youtube.com/embed/${videoId}?playsinline=1&rel=0&modestbranding=1&iv_load_policy=3`;
  
  const response = await fetch(embedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });

  if (!response.ok) {
    throw new Error(`YouTube embed fetch failed: ${response.status}`);
  }

  let html = await response.text();

  // Rewrite relative URLs to absolute (YouTube uses // and / relative paths)
  html = html.replace(/href="\//g, 'href="https://www.youtube.com/');
  html = html.replace(/src="\//g, 'src="https://www.youtube.com/');
  html = html.replace(/href="\/\//g, 'href="https://');
  html = html.replace(/src="\/\//g, 'src="https://');
  
  // Rewrite CSS url() references
  html = html.replace(/url\(\//g, 'url(https://www.youtube.com/');
  html = html.replace(/url\(\/\//g, 'url(https://');

  // Add a base tag to handle any remaining relative URLs
  html = html.replace('<head>', '<head><base href="https://www.youtube.com/">');

  // 🔧 v12.1: inject Safari shim IMMEDIATELY after <head>, BEFORE any YouTube scripts
  // This runs before YouTube's player JS loads, so when it checks window.safari,
  // navigator.vendor etc., it finds Safari-like values → no 153.
  html = html.replace('<head><base ', '<head>' + SAFARI_SHIM + '<base ');

  // Add viewport meta for mobile
  if (!html.includes('name="viewport"')) {
    html = html.replace('<head>', '<head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">');
  }

  return html;
}
