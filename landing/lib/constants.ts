// Ссылки на магазин берутся только из окружения. Заглушки вроде id0000000000
// здесь нет намеренно: кнопка, ведущая на несуществующую страницу, хуже
// честной надписи «скоро».
function envUrl(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export const APP_STORE_URL: string | null = envUrl(process.env.NEXT_PUBLIC_APP_STORE_URL);
export const TESTFLIGHT_URL: string | null = envUrl(process.env.NEXT_PUBLIC_TESTFLIGHT_URL);

export type StoreCta = {
  /** Куда ведёт кнопка; null — приложение ещё недоступно, кнопка неактивна. */
  href: string | null;
  /** Подпись кнопки для текущего состояния. */
  label: string;
  /** true только когда приложение опубликовано в App Store. */
  live: boolean;
};

/**
 * Единая точка правды для всех кнопок «Скачать»: App Store → TestFlight → «скоро».
 * Все CTA на сайте рендерятся через components/StoreCta.tsx и этот помощник.
 */
export function getStoreCta(): StoreCta {
  if (APP_STORE_URL) {
    return { href: APP_STORE_URL, label: 'Скачать в App Store', live: true };
  }
  if (TESTFLIGHT_URL) {
    return { href: TESTFLIGHT_URL, label: 'Открыть в TestFlight', live: false };
  }
  return { href: null, label: 'Скоро в App Store', live: false };
}

export const STORE_CTA = getStoreCta();

/** Статус iOS-клиента для бейджа в hero. */
export const STORE_STATUS_LABEL = STORE_CTA.live
  ? 'Уже в App Store'
  : STORE_CTA.href
    ? 'Бета в TestFlight'
    : 'Скоро в App Store';

// Where users are told to write. Import this rather than typing the address into
// a page: it appears on /terms, /privacy and in the FAQ, and it is wrong today —
// plink.app publishes a null MX record (`0 .`, RFC 7505), so the domain declares
// it accepts no mail and anything sent to this address is rejected before it is
// delivered. Choosing the real channel is the owner's call; keeping it in one
// place makes that change one line. The backend holds the same constant for the
// pages the iOS app links to (backend/src/web/legal.ts).
export const SUPPORT_EMAIL = 'support@plink.app';

export type PlatformStatus = 'available' | 'beta' | 'soon' | 'development';

// Честный статус платформ — iOS зависит от того, опубликовано ли приложение,
// остальные в разработке. Никаких фейковых скриншотов под несуществующие клиенты.
export const ECOSYSTEM_STATUS: ReadonlyArray<{
  platform: string;
  status: PlatformStatus;
  note: string;
}> = [
  {
    platform: 'iOS',
    status: STORE_CTA.live ? 'available' : STORE_CTA.href ? 'beta' : 'soon',
    note: STORE_CTA.live
      ? 'В App Store'
      : STORE_CTA.href
        ? 'Бета в TestFlight'
        : 'Скоро в App Store',
  },
  { platform: 'macOS', status: 'development', note: 'В разработке' },
  { platform: 'Windows', status: 'development', note: 'В разработке' },
  { platform: 'Android', status: 'development', note: 'В разработке' },
];

export const FAQ_DATA = [
  {
    q: 'Нужно ли всем участникам что-то скачивать?',
    a: 'Хосту — да (приложение). Гостям на YouTube достаточно открыть ссылку и нажать «Смотреть в браузере» — синхрон без установки. Для VK, Rutube и кинотеатров удобнее приложение.',
  },
  {
    q: 'Какие сервисы поддерживаются?',
    a: 'В синхроне: YouTube, VK Видео, Rutube и прямые ссылки на видео. Netflix, Disney+, Кинопоиск и другие кинотеатры с DRM синхронно не проигрываются: Plink не обходит DRM и не хранит чужие пароли.',
  },
  {
    q: 'Что будет, если кто-то нажмёт на паузу?',
    a: 'Видео остановится у всех сразу. Синхронно и без задержек — никто не смотрит в одиночку.',
  },
  {
    q: 'Что даёт Plink+?',
    a: 'Живые темы для комнат, премиальные реакции и кастомные темы для интерфейса. Смотреть вместе, чатиться и делать реакции можно бесплатно.',
  },
  {
    q: 'Как отменить подписку?',
    a: 'Настройки → Apple ID → Подписки → Plink. Нажмёте «Отменить» — сразу прекратится дебетование, доступ останется до конца оплаченного периода.',
  },
  {
    q: 'Будет ли Plink на Mac, Windows, Android?',
    a: 'Да, macOS и Windows в активной разработке. Сейчас полностью готов только iOS.',
  },
  {
    q: 'Нужен ли VPN для иностранных сервисов?',
    a: 'Plink не требует VPN. Но доступный контент зависит от вашего региона — как и в любом легальном сервисе.',
  },
] as const;

export const PRICING = {
  monthly: { price: 299, period: 'мес', usd: '$2.99' },
  yearly: { price: 2990, period: 'год', usd: '$29.99', monthlyEquivalent: 249 },
} as const;
