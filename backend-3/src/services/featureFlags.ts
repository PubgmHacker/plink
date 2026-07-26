// src/services/featureFlags.ts — Pack 5: Feature Flags
import { prisma } from '../config/db.js';
import { cacheGet, cacheSet, cacheDel } from '../config/redis.js';

const CACHE_KEY = 'feature_flags';
const CACHE_TTL = 60; // 1 min

export interface FeatureFlag {
  key: string;
  enabled: boolean;
  // Для процентного rollout
  rolloutPercentage?: number;
  // Для beta-testers
  enabledUserIds?: string[];
  // Для премиум-юзеров
  premiumOnly?: boolean;
}

const defaultFlags: FeatureFlag[] = [
  { key: 'youtube_search', enabled: true },
  { key: 'vk_extract', enabled: false },
  { key: 'rutube_extract', enabled: false },
  { key: 'netflix_webview', enabled: true },
  { key: 'storekit_premium', enabled: true },
  { key: 'referral_program', enabled: true },
  { key: 'live_activities', enabled: false },
  { key: 'airplay', enabled: true },
  { key: 'voice_chat', enabled: false },
  { key: 'screen_share', enabled: false },
  { key: 'ai_assistant', enabled: true, premiumOnly: true },
  { key: 'custom_themes', enabled: true, premiumOnly: true },
  { key: 'offline_cache', enabled: false },
];

export async function getFeatureFlags(): Promise<FeatureFlag[]> {
  const cached = await cacheGet<FeatureFlag[]>(CACHE_KEY);
  if (cached) return cached;
  
  // Try DB
  try {
    const dbFlags = await prisma.featureFlag.findMany();
    const flags = defaultFlags.map(defaultFlag => {
      const dbFlag = dbFlags.find(f => f.key === defaultFlag.key);
      return dbFlag 
        ? { ...defaultFlag, ...JSON.parse(dbFlag.value) }
        : defaultFlag;
    });
    await cacheSet(CACHE_KEY, flags, CACHE_TTL);
    return flags;
  } catch {
    // DB not ready — return defaults
    return defaultFlags;
  }
}

export async function isFeatureEnabled(
  key: string, 
  userId?: string, 
  isPremium?: boolean
): Promise<boolean> {
  const flags = await getFeatureFlags();
  const flag = flags.find(f => f.key === key);
  
  if (!flag || !flag.enabled) return false;
  
  // Premium-only check
  if (flag.premiumOnly && !isPremium) return false;
  
  // Beta tester check
  if (flag.enabledUserIds && flag.enabledUserIds.length > 0) {
    if (!userId || !flag.enabledUserIds.includes(userId)) return false;
  }
  
  // Percentage rollout
  if (flag.rolloutPercentage !== undefined && flag.rolloutPercentage < 100) {
    if (!userId) return false;
    // Hash userId to determine bucket (consistent per user)
    const hash = hashString(userId);
    const bucket = hash % 100;
    if (bucket >= flag.rolloutPercentage) return false;
  }
  
  return true;
}

export async function updateFeatureFlag(
  key: string, 
  value: Partial<FeatureFlag>
): Promise<void> {
  const flags = await getFeatureFlags();
  const flag = flags.find(f => f.key === key);
  if (!flag) throw new Error(`Flag ${key} not found`);
  
  const updated = { ...flag, ...value };
  
  await prisma.featureFlag.upsert({
    where: { key },
    update: { value: JSON.stringify(updated) },
    create: { key, value: JSON.stringify(updated) },
  });
  
  await cacheDel(CACHE_KEY);
}

// GET /api/feature-flags (для iOS — какие фичи включены для этого юзера)
export async function getUserFlags(userId: string, isPremium: boolean) {
  const flags = await getFeatureFlags();
  const result: Record<string, boolean> = {};
  
  for (const flag of flags) {
    result[flag.key] = await isFeatureEnabled(flag.key, userId, isPremium);
  }
  
  return result;
}

function hashString(s: string): number {
  let hash = 0;
  for (let i = 0; i < s.length; i++) {
    const char = s.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash);
}
