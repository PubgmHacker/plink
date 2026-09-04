// Pure helpers behind the profile statistics block: achievements with
// progress toward the next threshold and a 30-day activity digest.
//
// No Prisma in here on purpose — the route feeds counts and timestamps in,
// the unit test feeds synthetic ones. Thresholds live in one place so the
// iOS client never has to mirror them: it renders `progress / target` as is.

export type AchievementCode = 'regular' | 'cinemaniac' | 'social' | 'plink_plus';

export interface Achievement {
  code: AchievementCode;
  earned: boolean;
  /** Current value toward `target`, clamped to `target` once earned. */
  progress: number;
  target: number;
}

export interface AchievementInput {
  filmsWatched: number;
  friendsCount: number;
  isPremium: boolean;
}

/**
 * Thresholds. "Host" achievements were retired: room ownership is a
 * technical role (any member becomes host when the owner leaves), not an
 * accomplishment a regular user understands or earns.
 */
export const ACHIEVEMENT_TARGETS = {
  regular: 10,
  cinemaniac: 100,
  social: 50,
} as const;

function counter(code: AchievementCode, value: number, target: number): Achievement {
  const safe = Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0;
  return { code, earned: safe >= target, progress: Math.min(safe, target), target };
}

export function computeAchievements(input: AchievementInput): Achievement[] {
  return [
    counter('regular', input.filmsWatched, ACHIEVEMENT_TARGETS.regular),
    counter('cinemaniac', input.filmsWatched, ACHIEVEMENT_TARGETS.cinemaniac),
    counter('social', input.friendsCount, ACHIEVEMENT_TARGETS.social),
    {
      code: 'plink_plus',
      earned: Boolean(input.isPremium),
      progress: input.isPremium ? 1 : 0,
      target: 1,
    },
  ];
}

/** Earned codes only — the legacy `badges` array older clients still read. */
export function earnedBadges(achievements: Achievement[]): string[] {
  return achievements.filter((a) => a.earned).map((a) => a.code);
}

export interface ActivityEntry {
  watchedAt: Date;
  kind: string | null;
}

export interface ActivityDigest {
  /** Entries per calendar day for the last 7 days — oldest first, today last. */
  week: number[];
  weekFilms: number;
  monthFilms: number;
  /** Consecutive days with at least one entry, ending today or yesterday. */
  streakDays: number;
  /** Most frequent media kind over the last 30 days; null when nothing was watched. */
  topKind: string | null;
}

const DAY_MS = 86_400_000;

/**
 * Calendar-day index of an instant. `offsetMinutes` shifts the day boundary
 * to the viewer's zone (UTC+3 → 180) so a film started at 01:00 local counts
 * for that local day, not the UTC one.
 */
function dayIndex(at: Date, offsetMinutes: number): number {
  return Math.floor((at.getTime() + offsetMinutes * 60_000) / DAY_MS);
}

export function computeActivity(
  entries: ActivityEntry[],
  now: Date = new Date(),
  offsetMinutes = 0,
): ActivityDigest {
  const offset = Number.isFinite(offsetMinutes) ? Math.max(-840, Math.min(840, offsetMinutes)) : 0;
  const today = dayIndex(now, offset);
  const week = new Array<number>(7).fill(0);
  const days = new Set<number>();
  const kinds = new Map<string, number>();
  let monthFilms = 0;

  for (const entry of entries) {
    const at = entry.watchedAt instanceof Date ? entry.watchedAt : new Date(entry.watchedAt);
    if (Number.isNaN(at.getTime())) continue;
    const day = dayIndex(at, offset);
    if (day > today) continue; // clock skew — never count the future
    const age = today - day;
    if (age >= 30) continue;
    monthFilms += 1;
    days.add(day);
    if (age < 7) week[6 - age] += 1;
    if (entry.kind) kinds.set(entry.kind, (kinds.get(entry.kind) ?? 0) + 1);
  }

  // Streak may be "kept alive" by yesterday: the day is not over yet.
  let streakDays = 0;
  let cursor = days.has(today) ? today : days.has(today - 1) ? today - 1 : null;
  while (cursor !== null && days.has(cursor)) {
    streakDays += 1;
    cursor -= 1;
  }

  let topKind: string | null = null;
  let best = 0;
  for (const [kind, count] of kinds) {
    if (count > best) {
      best = count;
      topKind = kind;
    }
  }

  return {
    week,
    weekFilms: week.reduce((sum, n) => sum + n, 0),
    monthFilms,
    streakDays,
    topKind,
  };
}
