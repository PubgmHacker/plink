import { describe, expect, it } from 'vitest';
import {
  mediaTitleFromMediaItem,
  webWatchTargetFromMediaItem,
  youtubeIdFromMediaItem,
} from '../../web/watchPage.js';

describe('youtubeIdFromMediaItem', () => {
  it('reads videoId from JSON mediaItem', () => {
    expect(
      youtubeIdFromMediaItem(
        JSON.stringify({
          id: 'dQw4w9WgXcQ',
          videoId: 'dQw4w9WgXcQ',
          source: 'youtube',
          streamURL: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
        }),
      ),
    ).toBe('dQw4w9WgXcQ');
  });

  it('extracts from streamURL when videoId missing', () => {
    expect(
      youtubeIdFromMediaItem(
        JSON.stringify({
          id: 'custom',
          source: 'youtube',
          streamURL: 'https://youtu.be/abcdefghijk',
        }),
      ),
    ).toBe('abcdefghijk');
  });

  it('returns null for cinema / non-youtube', () => {
    expect(
      youtubeIdFromMediaItem(
        JSON.stringify({
          id: 'kp-1',
          source: 'kinopoisk',
          streamURL: 'https://www.kinopoisk.ru/film/123',
          title: 'Film',
        }),
      ),
    ).toBeNull();
  });
});

describe('mediaTitleFromMediaItem', () => {
  it('reads title from JSON', () => {
    expect(mediaTitleFromMediaItem(JSON.stringify({ title: 'Demo' }))).toBe('Demo');
  });
});

describe('webWatchTargetFromMediaItem', () => {
  it('builds youtube player src', () => {
    const t = webWatchTargetFromMediaItem(
      JSON.stringify({
        videoId: 'dQw4w9WgXcQ',
        source: 'youtube',
        streamURL: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      }),
    );
    expect(t?.kind).toBe('youtube');
    expect(t?.id).toBe('dQw4w9WgXcQ');
    expect(t?.playerSrc).toContain('youtube-player');
  });

  it('builds vk embed from group video path', () => {
    const t = webWatchTargetFromMediaItem(
      JSON.stringify({
        videoId: '-123_456',
        source: 'url',
        streamURL: 'https://vk.com/video-123_456',
      }),
    );
    expect(t?.kind).toBe('vk');
    expect(t?.id).toBe('-123_456');
    expect(t?.playerSrc).toBe('https://vk.com/video_ext.php?oid=-123&id=456&hd=2');
  });

  it('builds rutube embed from 32-hex id', () => {
    const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const t = webWatchTargetFromMediaItem(
      JSON.stringify({
        videoId: id,
        source: 'url',
        streamURL: `https://rutube.ru/video/${id}/`,
      }),
    );
    expect(t?.kind).toBe('rutube');
    expect(t?.id).toBe(id);
    expect(t?.playerSrc).toBe(`https://rutube.ru/play/embed/${id}`);
  });

  it('returns null for cinema / your-screen pages', () => {
    expect(
      webWatchTargetFromMediaItem(
        JSON.stringify({
          source: 'url',
          streamURL: 'https://www.netflix.com/title/80178687',
        }),
      ),
    ).toBeNull();
    expect(
      webWatchTargetFromMediaItem(
        JSON.stringify({
          source: 'kinopoisk',
          streamURL: 'https://www.kinopoisk.ru/film/123',
        }),
      ),
    ).toBeNull();
  });
});
