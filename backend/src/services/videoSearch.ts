// src/services/videoSearch.ts — поиск видео по нескольким хостингам
//
// /api/media/search раньше ходил только в YouTube Data API v3. В России
// YouTube отвечает не у всех, а комната умеет играть RuTube и VK Видео
// собственными embed-контроллерами — поиск был у́же плеера.
//
// Провайдеры:
//   youtube — Data API v3, нужен YOUTUBE_API_KEY (как и было);
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
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

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
  const total = parseInt(m[1] || '0', 10) * 3600
    + parseInt(m[2] || '0', 10) * 60
    + parseInt(m[3] || '0', 10);
  return total > 0 ? total : null;
}

// ─────────────────────────────────────────────────────────── YouTube

export async function searchYouTube(q: string, limit: number, apiKey: string): Promise<VideoSearchItem[]> {
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
        thumbnailURL: item.snippet?.thumbnails?.medium?.url
          || item.snippet?.thumbnails?.default?.url || null,
        duration: null,
        url: `https://www.youtube.com/watch?v=${videoId}`,
        provider: 'youtube',
        embedURL: `https://www.youtube.com/embed/${videoId}`,
        embeddable: null,
      };
    });
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
  // RuTube отвечает 200 и пустым results, когда режет запрос по региону,
  // — без этой строки «нет роликов» и «нас не пустили» выглядят одинаково.
  const rawCount = Array.isArray(data.results) ? data.results.length : -1;
  const items: VideoSearchItem[] = (data.results || [])
    // Взрослое — мимо витрины: комнату видят все участники.
    .filter((r: any) => r?.id && !r.is_adult)
    .map((r: any): VideoSearchItem => ({
      id: String(r.id),
      title: r.title || '',
      channel: r.author?.name || 'RuTube',
      thumbnailURL: r.thumbnail_url || null,
      duration: typeof r.duration === 'number' && r.duration > 0 ? r.duration : null,
      url: r.video_url || `https://rutube.ru/video/${r.id}/`,
      provider: 'rutube',
      embedURL: r.embed_url || `https://rutube.ru/play/embed/${r.id}`,
      embeddable: r.is_hidden === true ? false : null,
    }));
  // count — сколько совпадений насчитал сам RuTube. Если count большой,
  // а results пустой, значит хостинг отдал заглушку по IP, а не «не нашёл».
  if (items.length !== rawCount || items.length === 0) {
    console.warn(`rutube: count=${data.count ?? '?'} raw=${rawCount} kept=${items.length} q="${q}"`);
  }
  return items;
}

// ──────────────────────────────────────────────────────────── VK Видео

export async function searchVK(q: string, limit: number, token: string): Promise<VideoSearchItem[]> {
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
      const image = Array.isArray(v.image) && v.image.length
        ? v.image[v.image.length - 1]?.url
        : null;
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

/**
 * Опрашивает все настроенные хостинги параллельно. Падение одного не
 * роняет выдачу: пустой ответ вернётся, только если легли все.
 */
export async function searchAllProviders(
  q: string,
  limit: number,
  env: { youtubeKey?: string; vkToken?: string } = {},
): Promise<MultiSearchResult> {
  const perProvider = Math.max(6, Math.ceil(limit / 2));
  const tasks: { provider: string; run: () => Promise<VideoSearchItem[]> }[] = [];

  if (env.youtubeKey) {
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

  if (!env.youtubeKey) failed.push({ provider: 'youtube', reason: 'YOUTUBE_API_KEY not configured' });
  if (!env.vkToken) failed.push({ provider: 'vk', reason: 'VK_SERVICE_TOKEN not configured' });

  return { results: interleave(groups, limit), providers, failed, counts };
}
