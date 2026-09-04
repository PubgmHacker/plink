// Unit tests for the pure helpers behind GET /api/friends/stories.
import { describe, expect, it } from 'vitest';
import {
  STORY_SLIDES_PER_USER,
  groupStorySlides,
  orderStoryOwners,
  type StoryHistoryRow,
} from '../../utils/friendStories.js';

function row(
  userID: string,
  id: string,
  title: string | null,
  minutesAgo: number,
  extra: Partial<StoryHistoryRow> = {},
): StoryHistoryRow {
  return {
    id,
    userID,
    mediaTitle: title,
    mediaThumb: null,
    mediaKind: 'movie',
    watchedAt: new Date(Date.UTC(2026, 8, 3, 12, 0) - minutesAgo * 60_000),
    roomID: null,
    ...extra,
  };
}

describe('groupStorySlides', () => {
  it('groups rows per user, keeps newest-first order and ISO timestamps', () => {
    const rows = [
      row('a', '1', 'Dune', 5, { mediaThumb: 'https://x/dune.jpg', roomID: 'r1' }),
      row('b', '2', 'Alien', 10),
      row('a', '3', 'Heat', 20, { mediaKind: 'series' }),
    ];
    const grouped = groupStorySlides(rows);
    expect(grouped.get('a')?.map((s) => s.title)).toEqual(['Dune', 'Heat']);
    expect(grouped.get('b')?.map((s) => s.title)).toEqual(['Alien']);
    const dune = grouped.get('a')![0];
    expect(dune).toMatchObject({ id: '1', thumb: 'https://x/dune.jpg', roomId: 'r1', kind: 'movie' });
    expect(dune.watchedAt).toBe('2026-09-03T11:55:00.000Z');
    expect(grouped.get('a')![1].kind).toBe('series');
  });

  it('skips untitled rows and collapses repeats of one title into the newest watch', () => {
    const rows = [
      row('a', '1', null, 1),
      row('a', '2', '  ', 2),
      row('a', '3', 'Capsule check', 3),
      row('a', '4', 'capsule CHECK', 30),
      row('a', '5', 'Timing', 40),
    ];
    const slides = groupStorySlides(rows).get('a')!;
    expect(slides.map((s) => s.id)).toEqual(['3', '5']);
  });

  it('caps slides per user and ignores rows with a broken timestamp', () => {
    const rows: StoryHistoryRow[] = [];
    for (let i = 0; i < STORY_SLIDES_PER_USER + 5; i += 1) rows.push(row('a', String(i), `Film ${i}`, i));
    rows.push({ ...row('b', 'x', 'Broken', 1), watchedAt: 'not-a-date' });
    const grouped = groupStorySlides(rows);
    expect(grouped.get('a')).toHaveLength(STORY_SLIDES_PER_USER);
    expect(grouped.get('a')![0].title).toBe('Film 0');
    expect(grouped.has('b')).toBe(false);
  });
});

describe('orderStoryOwners', () => {
  it('keeps only people with a slide or a status, newest watch first, status-only last', () => {
    const owners = [
      { id: 'quiet', statusText: null, slides: [] },
      { id: 'status-only', statusText: 'Всегда за Дюну', slides: [] },
      { id: 'old', statusText: null, slides: [{ id: '1', title: 'A', thumb: null, kind: null, watchedAt: '2026-09-01T10:00:00.000Z', roomId: null }] },
      { id: 'fresh', statusText: '   ', slides: [{ id: '2', title: 'B', thumb: null, kind: null, watchedAt: '2026-09-03T10:00:00.000Z', roomId: null }] },
      { id: 'blank-status', statusText: '  ', slides: [] },
    ];
    expect(orderStoryOwners(owners).map((o) => o.id)).toEqual(['fresh', 'old', 'status-only']);
  });
});
