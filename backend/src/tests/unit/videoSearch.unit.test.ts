// videoSearch.unit.test.ts — поиск по видеохостингам без сети.
//
// Что здесь проверяется и почему:
//   1. Отсутствие ключа больше не роняет весь поиск — RuTube работает без
//      токена, и раньше пустой YOUTUBE_API_KEY отдавал 500 на весь запрос.
//   2. Падение одного провайдера не съедает выдачу остальных.
//   3. Интерлив: RuTube не должен тонуть под пачкой YouTube.
//   4. VK-эмбед собирается формой video_ext.php?oid=…&id=… — форма oid_id
//      отдаёт страницу без плеера.

import { describe, it, expect, vi, afterEach } from 'vitest';

import {
  parseISODuration,
  interleave,
  searchYouTube,
  searchRutube,
  searchVK,
  searchAllProviders,
  fetchWithRetry,
  type VideoSearchItem,
} from '../../services/videoSearch.js';

const realFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = realFetch;
  vi.restoreAllMocks();
});

/** Ответ-заглушка вместо сети. */
function jsonResponse(body: unknown, ok = true, status = 200): Response {
  return {
    ok,
    status,
    json: async () => body,
  } as unknown as Response;
}

function item(url: string, provider: string): VideoSearchItem {
  return {
    id: url,
    title: url,
    channel: provider,
    thumbnailURL: null,
    duration: null,
    url,
    provider,
    embedURL: null,
    embeddable: null,
  };
}

describe('parseISODuration', () => {
  it('разбирает часы, минуты и секунды', () => {
    expect(parseISODuration('PT1H30M15S')).toBe(5415);
    expect(parseISODuration('PT4M13S')).toBe(253);
    expect(parseISODuration('PT45S')).toBe(45);
  });

  it('отдаёт null там, где длительности нет', () => {
    expect(parseISODuration(null)).toBeNull();
    expect(parseISODuration(undefined)).toBeNull();
    expect(parseISODuration('P0D')).toBeNull();
    expect(parseISODuration('PT0S')).toBeNull();
  });
});

describe('interleave', () => {
  it('берёт по одному ряду с каждого провайдера, а не склеивает списки', () => {
    const yt = [item('y1', 'youtube'), item('y2', 'youtube'), item('y3', 'youtube')];
    const rt = [item('r1', 'rutube'), item('r2', 'rutube')];
    expect(interleave([yt, rt], 5).map((i) => i.url)).toEqual(['y1', 'r1', 'y2', 'r2', 'y3']);
  });

  it('режет дубли по ссылке и держит лимит', () => {
    const a = [item('same', 'youtube'), item('a2', 'youtube')];
    const b = [item('SAME', 'rutube'), item('b2', 'rutube')];
    const out = interleave([a, b], 3);
    expect(out.map((i) => i.url)).toEqual(['same', 'a2', 'b2']);
  });
});

describe('searchRutube', () => {
  it('раскладывает ответ RuTube и отбрасывает взрослое', async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({
        results: [
          {
            id: 'abc',
            title: 'Коты',
            author: { name: 'Канал' },
            thumbnail_url: 'https://pic/1.jpg',
            duration: 253,
            video_url: 'https://rutube.ru/video/abc/',
            embed_url: 'https://rutube.ru/play/embed/abc',
          },
          { id: 'adult', title: '18+', is_adult: true },
        ],
      }),
    ) as unknown as typeof fetch;

    const out = await searchRutube('коты', 10);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({
      provider: 'rutube',
      title: 'Коты',
      channel: 'Канал',
      duration: 253,
      url: 'https://rutube.ru/video/abc/',
      embedURL: 'https://rutube.ru/play/embed/abc',
    });
  });
});

describe('searchVK', () => {
  it('собирает эмбед формой video_ext.php с раздельными oid и id', async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({
        response: {
          items: [
            {
              owner_id: -12345,
              id: 678,
              title: 'Фильм',
              owner_text: 'Сообщество',
              duration: 5400,
              image: [{ url: 'https://vk/s.jpg' }, { url: 'https://vk/l.jpg' }],
              can_embed: 1,
            },
          ],
        },
      }),
    ) as unknown as typeof fetch;

    const out = await searchVK('фильм', 10, 'token');
    expect(out[0].embedURL).toBe('https://vk.com/video_ext.php?oid=-12345&id=678&hd=2&js_api=1');
    expect(out[0].url).toBe('https://vk.com/video-12345_678');
    expect(out[0].thumbnailURL).toBe('https://vk/l.jpg');
    expect(out[0].embeddable).toBe(true);
  });

  it('ошибку API поднимает наверх, а не отдаёт пустой список как успех', async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({ error: { error_code: 15, error_msg: 'Access denied: token required' } }),
    ) as unknown as typeof fetch;

    await expect(searchVK('фильм', 10, 'stale')).rejects.toThrow(/vk api 15/);
  });
});

describe('fetchWithRetry', () => {
  const noSleep = async () => {};

  it('повторяет запрос после 429 и отдаёт удачный ответ', async () => {
    let calls = 0;
    globalThis.fetch = vi.fn(async () => {
      calls += 1;
      return calls === 1 ? jsonResponse({}, false, 429) : jsonResponse({ ok: true });
    }) as unknown as typeof fetch;

    const resp = await fetchWithRetry('https://example.test/', {}, 2, 0, noSleep);
    expect(calls).toBe(2);
    expect(resp.status).toBe(200);
  });

  it('не повторяет 403 — это не заминка, а отказ', async () => {
    let calls = 0;
    globalThis.fetch = vi.fn(async () => {
      calls += 1;
      return jsonResponse({}, false, 403);
    }) as unknown as typeof fetch;

    const resp = await fetchWithRetry('https://example.test/', {}, 2, 0, noSleep);
    expect(calls).toBe(1);
    expect(resp.status).toBe(403);
  });

  it('после последней попытки возвращает сам 429, а не бросает', async () => {
    globalThis.fetch = vi.fn(async () => jsonResponse({}, false, 429)) as unknown as typeof fetch;

    const resp = await fetchWithRetry('https://example.test/', {}, 2, 0, noSleep);
    expect(resp.status).toBe(429);
  });
});

describe('searchAllProviders', () => {
  it('запрос к YouTube уходит с quotaUser — иначе лимит делится по IP Railway', async () => {
    let seen = '';
    globalThis.fetch = vi.fn(async (input: any) => {
      seen = String(input);
      return jsonResponse({ items: [] });
    }) as unknown as typeof fetch;

    await searchYouTube('коты', 6, 'key');
    expect(new URL(seen).searchParams.get('quotaUser')).toBe('plink-search');
  });

  it('без ключей отдаёт RuTube, а не 500 на весь поиск', async () => {
    globalThis.fetch = vi.fn(async () =>
      jsonResponse({ results: [{ id: 'r1', title: 'RT', video_url: 'https://rutube.ru/video/r1/' }] }),
    ) as unknown as typeof fetch;

    const res = await searchAllProviders('коты', 12, {});
    expect(res.providers).toEqual(['rutube']);
    expect(res.results.map((r) => r.provider)).toEqual(['rutube']);
    expect(res.failed.map((f) => f.provider).sort()).toEqual(['vk', 'youtube']);
    expect(res.failed.every((f) => f.reason.endsWith('not configured'))).toBe(true);
  });

  it('падение YouTube не забирает с собой выдачу RuTube', async () => {
    globalThis.fetch = vi.fn(async (input: any) => {
      const url = String(input);
      if (url.includes('googleapis.com')) return jsonResponse({}, false, 403);
      return jsonResponse({ results: [{ id: 'r1', title: 'RT', video_url: 'https://rutube.ru/video/r1/' }] });
    }) as unknown as typeof fetch;

    const res = await searchAllProviders('коты', 12, { youtubeKey: 'key' });
    expect(res.providers).toEqual(['rutube']);
    expect(res.results).toHaveLength(1);
    expect(res.failed.find((f) => f.provider === 'youtube')?.reason).toContain('403');
  });

  // Провайдер, ответивший пустотой, и провайдер, которого не спросили, —
  // разные вещи. В counts первый виден нулём, второго там нет вовсе.
  it('counts различает пустой ответ и неопрошенного провайдера', async () => {
    globalThis.fetch = vi.fn(async (input: any) => {
      const url = String(input);
      if (url.includes('rutube.ru')) return jsonResponse({ results: [] });
      return jsonResponse({
        items: [{ id: { videoId: 'y1' }, snippet: { title: 'YT', channelTitle: 'ch' } }],
      });
    }) as unknown as typeof fetch;

    const res = await searchAllProviders('коты', 12, { youtubeKey: 'key' });
    expect(res.counts).toEqual({ youtube: 1, rutube: 0 });
    expect(res.counts.vk).toBeUndefined();
    expect(res.providers.sort()).toEqual(['rutube', 'youtube']);
  });
});
