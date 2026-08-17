// src/services/streamExtractor.ts — YouTube stream extraction
// v12.0 (Jul 2026): MULTI-STRATEGY PARALLEL RACER.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export interface StreamInfo {
  id: string;
  title: string;
  author: string;
  thumbnailURL: string;
  streamURL: string | null;
  hlsURL: string | null;
  duration: number;
  isLive: boolean;
  extractor: string;
  formats?: StreamFormat[];
}

export interface StreamFormat {
  url: string;
  ext: string;
  resolution: string;
  vcodec: string;
  acodec: string;
  filesize: number;
  tbr: number;
}

export const UPSTREAM_USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

const PIPED_INSTANCES = [
  'https://api.piped.private.coffee',
  'https://pipedapi.adminforge.de',
  'https://pipedapi.r4fo.com',
  'https://piped-api.kavin.rocks',
];

export function extractYouTubeId(url: string): string | null {
  const shortMatch = url.match(/youtu\.be\/([\w-]{11})/);
  if (shortMatch) return shortMatch[1];
  const watchMatch = url.match(/[?&]v=([\w-]{11})/);
  if (watchMatch) return watchMatch[1];
  const embedMatch = url.match(/youtube\.com\/(?:embed|shorts|live)\/([\w-]{11})/);
  if (embedMatch) return embedMatch[1];
  if (/^[\w-]{11}$/.test(url)) return url;
  return null;
}

async function extractWithYtDlp(videoId: string): Promise<StreamInfo> {
  const { stdout } = await execFileAsync(
    'yt-dlp',
    [
      '-j',
      '--no-playlist',
      '--no-warnings',
      '--socket-timeout', '8',
      '--extractor-args', 'youtube:player_client=android,web',
      `https://www.youtube.com/watch?v=${videoId}`,
    ],
    { timeout: 12_000, maxBuffer: 64 * 1024 * 1024 },
  );

  const data: any = JSON.parse(stdout);
  const formats: any[] = Array.isArray(data.formats) ? data.formats : [];

  const muxed = formats
    .filter((f) =>
      f.vcodec && f.vcodec !== 'none' &&
      f.acodec && f.acodec !== 'none' &&
      (f.ext === 'mp4' || String(f.container ?? '').startsWith('mp4')))
    .sort((a, b) => (b.height ?? 0) - (a.height ?? 0));

  const hlsFormat = formats.find((f) => String(f.protocol ?? '').includes('m3u8') && f.manifest_url)
    ?? (data.is_live ? formats.find((f) => String(f.protocol ?? '').includes('m3u8')) : undefined);

  const best = muxed[0];
  const hlsURL: string | null = (hlsFormat?.manifest_url as string | undefined) ?? (hlsFormat?.url as string | undefined) ?? null;

  if (!best && !hlsURL) {
    throw new Error('yt-dlp: no muxed MP4 or HLS format');
  }

  return {
    id: videoId,
    title: data.title ?? 'Unknown',
    author: data.uploader ?? data.channel ?? 'Unknown',
    thumbnailURL: data.thumbnail ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    streamURL: best?.url ?? null,
    hlsURL,
    duration: data.duration ?? 0,
    isLive: Boolean(data.is_live),
    extractor: 'yt-dlp',
    formats: muxed.slice(0, 5).map((f) => ({
      url: f.url,
      ext: f.ext ?? 'mp4',
      resolution: f.height ? `${f.height}p` : 'unknown',
      vcodec: f.vcodec ?? 'h264',
      acodec: f.acodec ?? 'aac',
      filesize: f.filesize ?? f.filesize_approx ?? 0,
      tbr: f.tbr ?? 0,
    })),
  };
}

async function extractWithPiped(videoId: string): Promise<StreamInfo> {
  const attempt = async (instance: string): Promise<StreamInfo> => {
    const response = await fetch(`${instance}/streams/${videoId}`, {
      headers: { 'User-Agent': UPSTREAM_USER_AGENT },
      signal: AbortSignal.timeout(6_000),
    });
    if (!response.ok) throw new Error(`${instance} → HTTP ${response.status}`);

    const data: any = await response.json();
    const videoStreams: any[] = data.videoStreams ?? [];
    const muxed = videoStreams
      .filter((s: any) => s.videoOnly === false)
      .sort((a: any, b: any) => (parseInt(b.quality) || 0) - (parseInt(a.quality) || 0));

    const best = muxed[0];
    const hlsURL: string | null = (data.hls as string | undefined) ?? null;
    if (!best && !hlsURL) throw new Error(`${instance}: DASH-only (no muxed)`);

    return {
      id: videoId,
      title: data.title ?? 'Unknown',
      author: data.uploader ?? 'Unknown',
      thumbnailURL: data.thumbnailUrl ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
      streamURL: best?.url ?? null,
      hlsURL,
      duration: data.duration ?? 0,
      isLive: Boolean(data.livestream),
      extractor: 'piped',
    };
  };

  return Promise.any(PIPED_INSTANCES.map(attempt));
}

async function extractWithInnertube(videoId: string): Promise<StreamInfo> {
  const response = await fetch('https://www.youtube.com/youtubei/v1/player?prettyPrint=false', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'com.google.android.youtube/19.29.37 (Linux; U; Android 14) gzip',
    },
    body: JSON.stringify({
      context: {
        client: {
          clientName: 'ANDROID',
          clientVersion: '19.29.37',
          androidSdkVersion: 34,
          hl: 'en',
          gl: 'US',
        },
      },
      videoId,
      playbackContext: { contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS' } },
    }),
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) throw new Error(`innertube → HTTP ${response.status}`);

  const data: any = await response.json();
  const sd = data.streamingData;
  if (!sd) {
    throw new Error(`innertube: ${data.playabilityStatus?.status ?? 'no streamingData'} (${data.playabilityStatus?.reason ?? 'unknown'})`);
  }

  const muxed: any[] = (sd.formats ?? [])
    .filter((f: any) => f.url && f.mimeType && String(f.mimeType).includes('video/mp4'))
    .sort((a: any, b: any) => (b.height ?? 0) - (a.height ?? 0));
  const hlsURL: string | null = (sd.hlsManifestUrl as string | undefined) ?? null;
  if (!muxed.length && !hlsURL) throw new Error('innertube: no muxed/HLS formats');

  const details = data.videoDetails ?? {};
  const thumbs: any[] = details.thumbnail?.thumbnails ?? [];
  const thumbnail = thumbs.length > 0
    ? thumbs.sort((a: any, b: any) => (b.width ?? 0) - (a.width ?? 0))[0]?.url
    : null;

  return {
    id: videoId,
    title: details.title ?? 'Unknown',
    author: details.author ?? 'Unknown',
    thumbnailURL: thumbnail ?? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    streamURL: muxed[0]?.url ?? null,
    hlsURL,
    duration: Number(details.lengthSeconds ?? 0) || 0,
    isLive: Boolean(details.isLiveContent),
    extractor: 'innertube-android',
    formats: muxed.slice(0, 5).map((f: any) => ({
      url: f.url,
      ext: 'mp4',
      resolution: f.height ? `${f.height}p` : (f.qualityLabel ?? 'unknown'),
      vcodec: f.mimeType?.match(/codecs="([^"]+)/)?.[1]?.split(',')[0] ?? 'h264',
      acodec: f.mimeType?.match(/codecs="[^"]+,\s*([^"]+)/)?.[1] ?? 'aac',
      filesize: Number(f.contentLength ?? 0) || 0,
      tbr: f.bitrate ? Math.round(f.bitrate / 1000) : 0,
    })),
  };
}

function aggregateErrorMessage(error: unknown): string {
  if (error instanceof AggregateError) {
    return error.errors
      .map((e) => e instanceof Error ? e.message : String(e))
      .join(' | ');
  }
  return error instanceof Error ? error.message : String(error);
}

async function runExtractor(name: string, videoId: string, fn: (videoId: string) => Promise<StreamInfo>): Promise<StreamInfo> {
  const started = Date.now();
  try {
    const result = await fn(videoId);
    const playable = result.streamURL ? 'MP4' : 'HLS';
    console.log(`[streamExtractor] ${name} won in ${Date.now() - started}ms (${playable})`);
    return result;
  } catch (error) {
    console.warn(`[streamExtractor] ${name} failed in ${Date.now() - started}ms: ${aggregateErrorMessage(error)}`);
    throw error;
  }
}

/**
 * Main entry point for stream extraction.
 * v12.0: race yt-dlp, Piped, and Innertube Android in parallel and return
 * the first extractor that produces either a muxed MP4 streamURL or HLS URL.
 */
export async function extractStream(url: string): Promise<StreamInfo> {
  let parsed: URL | null = null;
  try {
    parsed = new URL(url);
  } catch {
    // Accept raw 11-character YouTube IDs below.
  }

  if (parsed && !['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Invalid URL protocol');
  }

  const videoId = extractYouTubeId(url);
  if (!videoId) {
    throw new Error('Only YouTube URLs are supported');
  }

  console.log(`[streamExtractor] YouTube video ${videoId} — racing yt-dlp, Piped, Innertube`);

  try {
    return await Promise.any([
      runExtractor('yt-dlp', videoId, extractWithYtDlp),
      runExtractor('piped', videoId, extractWithPiped),
      runExtractor('innertube', videoId, extractWithInnertube),
    ]);
  } catch (error) {
    throw new Error(`All extractors failed: ${aggregateErrorMessage(error)}`);
  }
}

/**
 * Extract metadata only (no stream URL required by callers).
 * Uses the same racer so metadata follows the most reliable working strategy.
 */
export async function extractMetadata(url: string): Promise<Partial<StreamInfo>> {
  const stream = await extractStream(url);
  return {
    id: stream.id,
    title: stream.title,
    author: stream.author,
    thumbnailURL: stream.thumbnailURL,
    duration: stream.duration,
    isLive: stream.isLive,
    extractor: stream.extractor,
  };
}

/**
 * Convenience wrapper for YouTube video ID directly.
 */
export async function extractYouTubeStream(videoId: string): Promise<StreamInfo> {
  return extractStream(`https://www.youtube.com/watch?v=${videoId}`);
}
