import { describe, expect, it } from 'vitest';
import { mediaTitleFromMediaItem, youtubeIdFromMediaItem } from '../../web/watchPage.js';

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
