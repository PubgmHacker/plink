// Unit tests for the pure profile statistics helpers: achievement progress
// and the 30-day activity digest behind /users/:id/profile.
import { describe, expect, it } from 'vitest';
import {
  ACHIEVEMENT_TARGETS,
  computeAchievements,
  computeActivity,
  earnedBadges,
} from '../../utils/profileStats.js';

const DAY = 86_400_000;
const NOW = new Date('2026-09-03T12:00:00Z');
const at = (daysAgo: number, hour = 12) => new Date(NOW.getTime() - daysAgo * DAY + (hour - 12) * 3_600_000);

describe('computeAchievements', () => {
  it('reports progress toward every threshold, clamped once earned', () => {
    const list = computeAchievements({ filmsWatched: 12, friendsCount: 3, isPremium: false });
    const byCode = Object.fromEntries(list.map((a) => [a.code, a]));
    expect(byCode.regular).toEqual({ code: 'regular', earned: true, progress: 10, target: 10 });
    expect(byCode.cinemaniac).toEqual({ code: 'cinemaniac', earned: false, progress: 12, target: 100 });
    expect(byCode.social).toEqual({ code: 'social', earned: false, progress: 3, target: 50 });
    expect(byCode.plink_plus).toEqual({ code: 'plink_plus', earned: false, progress: 0, target: 1 });
  });

  it('never emits host achievements — room ownership is a role, not an award', () => {
    const codes = computeAchievements({ filmsWatched: 500, friendsCount: 500, isPremium: true }).map((a) => a.code);
    expect(codes).not.toContain('host');
    expect(codes).not.toContain('host_rising');
    expect(codes).toEqual(['regular', 'cinemaniac', 'social', 'plink_plus']);
  });

  it('tolerates garbage counters', () => {
    const list = computeAchievements({ filmsWatched: Number.NaN, friendsCount: -4, isPremium: true });
    expect(list.every((a) => a.progress >= 0 && a.progress <= a.target)).toBe(true);
    expect(list.find((a) => a.code === 'plink_plus')?.earned).toBe(true);
  });

  it('earnedBadges keeps the legacy badges array in sync', () => {
    const list = computeAchievements({
      filmsWatched: ACHIEVEMENT_TARGETS.cinemaniac,
      friendsCount: ACHIEVEMENT_TARGETS.social,
      isPremium: false,
    });
    expect(earnedBadges(list)).toEqual(['regular', 'cinemaniac', 'social']);
  });
});

describe('computeActivity', () => {
  it('returns an empty digest for a fresh account', () => {
    expect(computeActivity([], NOW)).toEqual({
      week: [0, 0, 0, 0, 0, 0, 0],
      weekFilms: 0,
      monthFilms: 0,
      streakDays: 0,
      topKind: null,
    });
  });

  it('buckets the last seven days oldest-first with today last', () => {
    const digest = computeActivity(
      [
        { watchedAt: at(0), kind: 'movie' },
        { watchedAt: at(0), kind: 'movie' },
        { watchedAt: at(1), kind: 'series' },
        { watchedAt: at(6), kind: 'movie' },
        { watchedAt: at(7), kind: 'video' }, // outside the week, inside the month
        { watchedAt: at(31), kind: 'video' }, // outside the month
      ],
      NOW,
    );
    expect(digest.week).toEqual([1, 0, 0, 0, 0, 1, 2]);
    expect(digest.weekFilms).toBe(4);
    expect(digest.monthFilms).toBe(5);
    expect(digest.topKind).toBe('movie');
  });

  it('counts a streak that ends today or is kept alive by yesterday', () => {
    const today = computeActivity([at(0), at(1), at(2)].map((d) => ({ watchedAt: d, kind: null })), NOW);
    expect(today.streakDays).toBe(3);
    const yesterday = computeActivity([at(1), at(2)].map((d) => ({ watchedAt: d, kind: null })), NOW);
    expect(yesterday.streakDays).toBe(2);
    const broken = computeActivity([at(2), at(3)].map((d) => ({ watchedAt: d, kind: null })), NOW);
    expect(broken.streakDays).toBe(0);
  });

  it('ignores future timestamps and invalid dates', () => {
    const digest = computeActivity(
      [
        { watchedAt: new Date(NOW.getTime() + 2 * DAY), kind: 'movie' },
        { watchedAt: new Date('not a date'), kind: 'movie' },
        { watchedAt: at(0), kind: 'series' },
      ],
      NOW,
    );
    expect(digest.weekFilms).toBe(1);
    expect(digest.topKind).toBe('series');
  });

  it('shifts day boundaries by the viewer offset', () => {
    // 23:30 UTC yesterday is already "today" in UTC+3.
    const lateNight = new Date('2026-09-02T23:30:00Z');
    const utc = computeActivity([{ watchedAt: lateNight, kind: null }], NOW, 0);
    const moscow = computeActivity([{ watchedAt: lateNight, kind: null }], NOW, 180);
    expect(utc.week[5]).toBe(1);
    expect(moscow.week[6]).toBe(1);
  });
});
