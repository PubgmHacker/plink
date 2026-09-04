// Pure helpers behind GET /api/friends/stories — the Telegram-style "stories"
// rail on the Friends tab, where a story is what a friend watched recently
// (plus their custom status as the opening slide).
//
// No Prisma in here: the route feeds history rows in, the unit test feeds
// synthetic ones. Windows and caps live in one place.

/** How far back a watch counts as "recent" — one week, not Telegram's 24h:
 *  a watch-together app has evenings, not a feed. */
export const STORY_WINDOW_MS = 7 * 86_400_000;
/** Slides per person. Enough for a week of evenings, short enough to tap through. */
export const STORY_SLIDES_PER_USER = 8;

export interface StoryHistoryRow {
  id: string;
  userID: string;
  mediaTitle: string | null;
  mediaThumb: string | null;
  mediaKind: string | null;
  watchedAt: Date | string;
  roomID: string | null;
}

export interface StorySlide {
  id: string;
  title: string;
  thumb: string | null;
  kind: string | null;
  /** ISO timestamp. */
  watchedAt: string;
  roomId: string | null;
}

/**
 * Groups history rows (already sorted newest first) into per-user slide lists.
 * Rows without a title are skipped — a slide has to name what was watched.
 * Repeats of the same title inside one person's window collapse into the
 * newest occurrence: a room restarted three times is one film, not three.
 */
export function groupStorySlides(
  rows: StoryHistoryRow[],
  perUser = STORY_SLIDES_PER_USER,
): Map<string, StorySlide[]> {
  const out = new Map<string, StorySlide[]>();
  const seenTitles = new Map<string, Set<string>>();
  for (const row of rows) {
    const title = (row.mediaTitle ?? '').trim();
    if (!title) continue;
    const at = row.watchedAt instanceof Date ? row.watchedAt : new Date(row.watchedAt);
    if (Number.isNaN(at.getTime())) continue;
    const slides = out.get(row.userID) ?? [];
    if (slides.length >= perUser) continue;
    const key = title.toLowerCase();
    const titles = seenTitles.get(row.userID) ?? new Set<string>();
    if (titles.has(key)) continue;
    titles.add(key);
    seenTitles.set(row.userID, titles);
    slides.push({
      id: row.id,
      title,
      thumb: row.mediaThumb ?? null,
      kind: row.mediaKind ?? null,
      watchedAt: at.toISOString(),
      roomId: row.roomID ?? null,
    });
    out.set(row.userID, slides);
  }
  return out;
}

export interface StoryOwnerInput {
  id: string;
  statusText: string | null;
  slides: StorySlide[];
}

/**
 * Who gets a ring: anyone with at least one slide or a status. Ordered by the
 * newest watch first; status-only people go last (alphabetical by id is
 * stable enough — the client shows names, not ids).
 */
export function orderStoryOwners<T extends StoryOwnerInput>(owners: T[]): T[] {
  const hasStory = (o: T) => o.slides.length > 0 || Boolean((o.statusText ?? '').trim());
  const latest = (o: T) => (o.slides.length ? Date.parse(o.slides[0].watchedAt) : Number.NEGATIVE_INFINITY);
  return owners
    .filter(hasStory)
    .sort((a, b) => {
      const la = latest(a);
      const lb = latest(b);
      if (la !== lb) return lb - la;
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
}
