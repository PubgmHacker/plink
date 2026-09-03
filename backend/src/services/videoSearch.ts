// src/services/videoSearch.ts — поиск видео по нескольким хостингам
//
// /api/media/search раньше ходил только в YouTube Data API v3. В России
// YouTube отвечает не у всех, а комната умеет играть RuTube и VK Видео
// собственными embed-контроллерами — поиск был у́же плеера.
//
// Провайдеры:
//   youtube — публичная страница результатов, ключ не нужен для beta-пути;
//             Data API v3 остаётся резервным адаптером для старых установок;
//   rutube  — https://rutube.ru/api/search/video/, ключ не нужен;
//   vk      — api.vk.com/method/video.search, нужен VK_SERVICE_TOKEN
//             (проверено 26.08.2026: без токена метод отдаёт
//              error_code 15 «Access denied: token required»).
//
// Провайдер без ключа просто не участвует в выдаче — 500 на весь поиск
// из-за одного отсутствующего токена был бы регрессом.

export interface VideoSearchItem {
  id: string;
  title: string;
  channel: string;
  thumbnailURL: string | null;
  /** Длительность в секундах; null — неизвестна (YouTube search её не отдаёт). */
  duration: number | null;
  /** Страница просмотра. Клиент определяет сервис по хосту этой ссылки. */
  url: string;
  /** Имя провайдера: youtube | rutube | vk. */
  provider: string;
  /** Прямая ссылка на плеер, если хостинг её публикует. */
  embedURL: string | null;
  /** false — хостинг явно запретил встраивание. */
  embeddable: boolean | null;
}

const TIMEOUT_MS = 10_000;
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;

/** Одна повторная попытка на 503 — заминка у провайдера не должна оставлять
 *  пользователя с пустой лентой. Пауза фиксированная: выдача ждёт синхронно,
 *  и разброс тут только мешал бы воспроизводимости.
 *
 *  429 сюда намеренно не входит. У YouTube это не «притормози», а исчерпанная
 *  суточная квота проекта (см. searchYouTube) — повтор не может её дождаться
 *  и лишь удваивает расход. Ждать бесполезное — хуже, чем не ждать. */
export async function fetchWithRetry(
  url: string,
  init: RequestInit,
  tries = 2,
  pauseMs = 400,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
): Promise<Response> {
  let last: Response | undefined;
  for (let attempt = 0; attempt < tries; attempt += 1) {
    const resp = await fetch(url, init);
    if (resp.status !== 503) return resp;
    last = resp;
    if (attempt < tries - 1) await sleep(pauseMs);
  }
  return last as Response;
}

/** ISO 8601 (PT1H30M15S) → секунды. */
export function parseISODuration(raw: string | undefined | null): number | null {
  if (!raw) return null;
  const m = raw.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return null;
  const total =
    parseInt(m[1] || '0', 10) * 3600 + parseInt(m[2] || '0', 10) * 60 + parseInt(m[3] || '0', 10);
  return total > 0 ? total : null;
}

// ─────────────────────────────────────────────────────────── YouTube

export async function searchYouTube(
  q: string,
  limit: number,
  apiKey: string,
): Promise<VideoSearchItem[]> {
  const url = new URL('https://www.googleapis.com/youtube/v3/search');
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('q', q);
  url.searchParams.set('type', 'video');
  url.searchParams.set('maxResults', String(limit));
  url.searchParams.set('key', apiKey);

  const resp = await fetchWithRetry(url.toString(), { signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!resp.ok) {
    // 429 у YouTube приходит с одной-единственной причиной: search.list стоит
    // 100 единиц из 10 000 суточных, то есть сто поисков в сутки на проект,
    // и они кончаются к середине дня. Замерено 26.08.2026: лимит зовётся
    // defaultSearchListPerDayPerProject, единица — 1/d/{project}. Отсюда два
    // следствия. Первое: quotaUser не лечит, он делит per-user вёдра, а
    // упирается проектное — проверено А/Б с параметром и без (0 из 6 в обеих
    // половинах). Второе: причину надо назвать, иначе в логе стоит голое
    // «youtube 429» и суточный потолок неотличим от сбоя сети.
    throw new Error(`youtube ${resp.status}${resp.status === 429 ? ' daily quota' : ''}`);
  }
  const data: any = await resp.json();
  return (data.items || [])
    .filter((item: any) => item.id?.videoId)
    .map((item: any): VideoSearchItem => {
      const videoId = item.id.videoId;
      return {
        id: videoId,
        title: item.snippet?.title || '',
        channel: item.snippet?.channelTitle || '',
        thumbnailURL:
          item.snippet?.thumbnails?.medium?.url || item.snippet?.thumbnails?.default?.url || null,
        duration: null,
        url: `https://www.youtube.com/watch?v=${videoId}`,
        provider: 'youtube',
        embedURL: `https://www.youtube.com/embed/${videoId}`,
        embeddable: null,
      };
    });
}

// ───────────────────────────────────────────────────── YouTube web search

/**
 * Reads the public YouTube results document instead of the Data API.
 *
 * This is intentionally kept separate from `searchYouTube`: the latter is a
 * compatibility adapter for installations that still opt into a Data API key,
 * while the product route uses this keyless path so a project quota cannot take
 * the beta search down. The parser accepts the two shapes YouTube currently
 * uses for text and duration and fails closed for malformed markup.
 */
export function parseYouTubeSearchHTML(html: string, limit: number): VideoSearchItem[] {
  const root = extractInitialData(html);
  if (!root) return [];

  const renderers: Record<string, unknown>[] = [];
  const walk = (node: unknown): void => {
    if (Array.isArray(node)) {
      node.forEach(walk);
      return;
    }
    if (!node || typeof node !== 'object') return;
    const record = node as Record<string, unknown>;
    const renderer = record.videoRenderer;
    if (renderer && typeof renderer === 'object' && !Array.isArray(renderer)) {
      renderers.push(renderer as Record<string, unknown>);
    }
    Object.values(record).forEach(walk);
  };
  walk(root);

  const seen = new Set<string>();
  const out: VideoSearchItem[] = [];
  for (const renderer of renderers) {
    if (out.length >= limit) break;
    const id = typeof renderer.videoId === 'string' ? renderer.videoId : '';
    const title = textValue(renderer.title);
    if (!YOUTUBE_ID.test(id) || !title || seen.has(id)) continue;

    // Live streams and scheduled premieres do not have a stable timeline for
    // all viewers, so they are not offered as a synchronized room source.
    if (renderer.isLive === true || renderer.upcomingEventData) continue;
    const durationText = textValue(renderer.lengthText);
    const duration = durationText ? parseClockDuration(durationText) : null;
    // Results without a finite timeline are live/upcoming/placeholder rows.
    // They cannot be started deterministically in a synchronized room.
    if (!duration) continue;

    const thumbnails = (renderer.thumbnail as Record<string, unknown> | undefined)?.thumbnails;
    const thumbnailList = Array.isArray(thumbnails) ? thumbnails : [];
    const thumbnail =
      thumbnailList
        .filter((value): value is Record<string, unknown> =>
          Boolean(value && typeof value === 'object'),
        )
        .map((value) => value.url)
        .filter((value): value is string => typeof value === 'string' && /^https?:\/\//.test(value))
        .pop() ?? null;

    seen.add(id);
    out.push({
      id,
      title,
      channel: textValue(renderer.ownerText) || textValue(renderer.longBylineText) || 'YouTube',
      thumbnailURL: thumbnail,
      duration,
      url: `https://www.youtube.com/watch?v=${id}`,
      provider: 'youtube',
      embedURL: `https://www.youtube.com/embed/${id}`,
      embeddable: null,
    });
  }
  return out;
}

/** Search the public results page, with a mobile-page fallback. */
export async function searchYouTubeWeb(q: string, limit: number): Promise<VideoSearchItem[]> {
  // Do not send the old duration filter (`sp=EgIQAQ==`): YouTube occasionally
  // rejects that encoded value as a malformed request. We filter live rows and
  // require a real duration in the parser instead.
  const query = new URLSearchParams({ search_query: q, hl: 'ru', gl: 'RU' });
  const urls = [
    `https://www.youtube.com/results?${query.toString()}`,
    `https://m.youtube.com/results?${query.toString()}`,
  ];
  let lastStatus = 0;
  for (const url of urls) {
    const resp = await fetchWithRetry(url, {
      headers: { 'User-Agent': UA, 'Accept-Language': 'ru-RU,ru;q=0.9' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    lastStatus = resp.status;
    if (!resp.ok) continue;
    const html = await resp.text();
    const results = parseYouTubeSearchHTML(html, limit);
    if (results.length > 0) return results;
  }
  throw new Error(`youtube web ${lastStatus || 'unavailable'}`);
}

/** Extract the balanced JSON object assigned to one of YouTube's bootstrap vars. */
export function extractInitialData(html: string): unknown | null {
  const markers = ['var ytInitialData =', 'ytInitialData =', 'window["ytInitialData"] ='];
  let markerEnd = -1;
  for (const marker of markers) {
    const markerStart = html.indexOf(marker);
    if (markerStart >= 0) {
      markerEnd = Math.max(markerEnd, markerStart + marker.length);
    }
  }
  if (markerEnd < 0) return null;
  const open = html.indexOf('{', markerEnd);
  if (open < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = open; i < html.length; i += 1) {
    const char = html[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
      continue;
    }
    if (char === '{') depth += 1;
    if (char === '}' && --depth === 0) {
      try {
        return JSON.parse(html.slice(open, i + 1));
      } catch {
        return null;
      }
    }
  }
  return null;
}

function textValue(value: unknown): string {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  const record = value as Record<string, unknown>;
  if (typeof record.simpleText === 'string') return record.simpleText;
  if (!Array.isArray(record.runs)) return '';
  return record.runs
    .filter((run): run is Record<string, unknown> => Boolean(run && typeof run === 'object'))
    .map((run) => (typeof run.text === 'string' ? run.text : ''))
    .join('');
}

export function parseClockDuration(raw: string): number | null {
  const match = raw.trim().match(/^(\d{1,4}):([0-5]?\d)(?::([0-5]?\d))?$/);
  if (!match) {
    return null;
  }
  const first = Number.parseInt(match[1], 10);
  const second = Number.parseInt(match[2], 10);
  const third = match[3] ? Number.parseInt(match[3], 10) : null;
  const seconds = third === null ? first * 60 + second : first * 3600 + second * 60 + third;
  return seconds > 0 ? seconds : null;
}

/** Providers sometimes return duration as a number, clock text, or ISO-8601. */
export function parseVideoDuration(raw: unknown): number | null {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : null;
  }
  if (typeof raw !== 'string') return null;
  const value = raw.trim();
  if (!value) return null;
  if (/^PT/i.test(value)) return parseISODuration(value);
  if (/^\d+$/.test(value)) {
    const seconds = Number(value);
    return Number.isSafeInteger(seconds) && seconds > 0 ? seconds : null;
  }
  return parseClockDuration(value);
}

// ──────────────────────────────────────────────────────────── RuTube

export async function searchRutube(q: string, limit: number): Promise<VideoSearchItem[]> {
  const url = new URL('https://rutube.ru/api/search/video/');
  url.searchParams.set('query', q);
  url.searchParams.set('limit', String(Math.min(limit, 20)));

  const resp = await fetch(url.toString(), {
    headers: { 'User-Agent': UA, Accept: 'application/json' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!resp.ok) {
    throw new Error(`rutube ${resp.status}`);
  }
  const data: any = await resp.json();
  const items: VideoSearchItem[] = (Array.isArray(data?.results) ? data.results : [])
    // Комнату видят все участники: скрытые, удалённые, adult, live и
    // платные/заблокированные карточки не должны попадать в beta-плеер.
    .filter((r: any) => {
      const id = typeof r?.id === 'string' || typeof r?.id === 'number' ? String(r.id).trim() : '';
      const title = typeof r?.title === 'string' ? r.title.trim() : '';
      return (
        Boolean(id && title) &&
        !r.is_adult &&
        !r.is_livestream &&
        !r.is_on_air &&
        !r.is_deleted &&
        !r.is_hidden &&
        !r.is_locked &&
        !r.is_paid &&
        // Missing duration is tolerated (some public rows omit it), while an
        // explicitly malformed value such as "LIVE" is a placeholder row.
        (r.duration === undefined || r.duration === null || parseVideoDuration(r.duration) !== null)
      );
    })
    .map((r: any): VideoSearchItem => {
      const id = String(r.id).trim();
      const thumbnail =
        typeof r.thumbnail_url === 'string' && /^https?:\/\//.test(r.thumbnail_url)
          ? r.thumbnail_url
          : null;
      return {
        id,
        title: String(r.title).trim(),
        channel:
          typeof r.author?.name === 'string' && r.author.name.trim()
            ? r.author.name.trim()
            : 'RuTube',
        thumbnailURL: thumbnail,
        duration: parseVideoDuration(r.duration),
        url: `https://rutube.ru/video/${encodeURIComponent(id)}/`,
        provider: 'rutube',
        embedURL: `https://rutube.ru/play/embed/${encodeURIComponent(id)}`,
        embeddable: null,
      };
    });
  // The count is deliberately not logged here: this service is also used by
  // the client-side search path, where a library function has no request logger.
  // The route records provider counts through Fastify's structured logger.
  return items;
}

// ──────────────────────────────────────────────────────────── VK Видео

export async function searchVK(
  q: string,
  limit: number,
  token: string,
): Promise<VideoSearchItem[]> {
  const url = new URL('https://api.vk.com/method/video.search');
  url.searchParams.set('q', q);
  url.searchParams.set('count', String(Math.min(limit, 50)));
  url.searchParams.set('adult', '0');
  url.searchParams.set('v', '5.199');
  url.searchParams.set('access_token', token);

  const resp = await fetch(url.toString(), { signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!resp.ok) {
    throw new Error(`vk ${resp.status}`);
  }
  const data: any = await resp.json();
  if (data.error) {
    // Ключ протух или у него нет прав — это не 500 всего поиска.
    throw new Error(`vk api ${data.error.error_code}: ${data.error.error_msg}`);
  }
  return (data.response?.items || [])
    .filter((v: any) => v?.owner_id !== undefined && v?.id !== undefined)
    .map((v: any): VideoSearchItem => {
      const oid = String(v.owner_id);
      const vid = String(v.id);
      // Плеер несёт только video_ext.php с раздельными oid и id —
      // форма oid_id отдаёт страницу без плеера (проверено на клиенте).
      const embed = `https://vk.com/video_ext.php?oid=${oid}&id=${vid}&hd=2&js_api=1`;
      const image =
        Array.isArray(v.image) && v.image.length ? v.image[v.image.length - 1]?.url : null;
      return {
        id: `${oid}_${vid}`,
        title: v.title || '',
        channel: v.owner_text || 'VK Видео',
        thumbnailURL: image || v.photo_320 || v.photo_130 || null,
        duration: typeof v.duration === 'number' && v.duration > 0 ? v.duration : null,
        url: `https://vk.com/video${oid}_${vid}`,
        provider: 'vk',
        embedURL: embed,
        // can_embed приходит не всегда; отсутствие поля ≠ запрет.
        embeddable: v.can_embed === undefined ? null : v.can_embed === 1,
      };
    });
}

// ─────────────────────────────────────────────────────── Склейка

/**
 * Интерлив: первый ряд каждого живого провайдера, потом второй и так
 * далее. Конкатенация утопила бы RuTube под тридцатью роликами YouTube.
 * Дубли режутся по ссылке.
 */
export function interleave(groups: VideoSearchItem[][], limit: number): VideoSearchItem[] {
  const out: VideoSearchItem[] = [];
  const seen = new Set<string>();
  const depth = Math.max(0, ...groups.map((g) => g.length));
  for (let i = 0; i < depth && out.length < limit; i += 1) {
    for (const group of groups) {
      if (out.length >= limit) break;
      const item = group[i];
      if (!item) continue;
      const key = item.url.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(item);
    }
  }
  return out;
}

export interface MultiSearchResult {
  results: VideoSearchItem[];
  /** Провайдеры, которые реально ответили. */
  providers: string[];
  /** Провайдеры, которые упали или не настроены — с причиной. */
  failed: { provider: string; reason: string }[];
  /** Сколько роликов дал каждый ответивший провайдер — до склейки. */
  counts: Record<string, number>;
}

export interface ProviderSearchOptions {
  youtubeKey?: string;
  vkToken?: string;
  /** Use the public YouTube page instead of the quota-bound Data API. */
  useYouTubeWeb?: boolean;
}

/**
 * Опрашивает все настроенные хостинги параллельно. Падение одного не
 * роняет выдачу: пустой ответ вернётся, только если легли все.
 */
export async function searchAllProviders(
  q: string,
  limit: number,
  env: ProviderSearchOptions = {},
): Promise<MultiSearchResult> {
  const perProvider = Math.max(6, Math.ceil(limit / 2));
  const tasks: { provider: string; run: () => Promise<VideoSearchItem[]> }[] = [];

  if (env.useYouTubeWeb) {
    tasks.push({
      provider: 'youtube',
      run: async () => {
        try {
          return await searchYouTubeWeb(q, perProvider);
        } catch (webError) {
          // Some egress IPs receive a bot/consent page from YouTube. If an
          // installation has explicitly configured the legacy key, use it as
          // a provider-local fallback; RuTube must remain independent of this.
          if (!env.youtubeKey) throw webError;
          return searchYouTube(q, perProvider, env.youtubeKey);
        }
      },
    });
  } else if (env.youtubeKey) {
    tasks.push({ provider: 'youtube', run: () => searchYouTube(q, perProvider, env.youtubeKey!) });
  }
  tasks.push({ provider: 'rutube', run: () => searchRutube(q, perProvider) });
  if (env.vkToken) {
    tasks.push({ provider: 'vk', run: () => searchVK(q, perProvider, env.vkToken!) });
  }

  const settled = await Promise.allSettled(tasks.map((t) => t.run()));
  const groups: VideoSearchItem[][] = [];
  const providers: string[] = [];
  const failed: { provider: string; reason: string }[] = [];
  const counts: Record<string, number> = {};

  settled.forEach((res, i) => {
    const name = tasks[i].provider;
    if (res.status === 'fulfilled') {
      providers.push(name);
      counts[name] = res.value.length;
      groups.push(res.value);
    } else {
      failed.push({ provider: name, reason: String(res.reason?.message || res.reason) });
    }
  });

  if (!env.useYouTubeWeb && !env.youtubeKey) {
    failed.push({ provider: 'youtube', reason: 'YOUTUBE_API_KEY not configured' });
  }
  if (!env.vkToken) failed.push({ provider: 'vk', reason: 'VK_SERVICE_TOKEN not configured' });

  return { results: interleave(groups, limit), providers, failed, counts };
}
