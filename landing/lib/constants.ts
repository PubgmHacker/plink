/** Replace id0000000000 when the App Store listing is live (set via env in deploy). */
export const APP_STORE_URL =
  process.env.NEXT_PUBLIC_APP_STORE_URL ?? 'https://apps.apple.com/app/plink/id0000000000';
export const TESTFLIGHT_URL = process.env.NEXT_PUBLIC_TESTFLIGHT_URL ?? '';
export const SUPPORT_EMAIL = 'support@plink.app';

// Честный статус платформ — iOS готов, остальные в разработке.
// Никаких фейковых скриншотов под несуществующие клиенты.
export const ECOSYSTEM_STATUS = [
  { platform: 'iOS', status: 'available' as const, note: 'В App Store' },
  { platform: 'macOS', status: 'development' as const, note: 'В разработке' },
  { platform: 'Windows', status: 'development' as const, note: 'В разработке' },
  { platform: 'Android', status: 'development' as const, note: 'В разработке' },
];

export const FAQ_DATA = [
  {
    q: 'Нужно ли всем участникам что-то скачивать?',
    a: 'Хосту — да (приложение). Гостям на YouTube достаточно открыть ссылку и нажать «Смотреть в браузере» — синхрон без установки. Для VK, Rutube и кинотеатров удобнее приложение.',
  },
  {
    q: 'Какие сервисы поддерживаются?',
    a: 'Сразу в синхроне: YouTube, VK Видео, Rutube и прямые ссылки. Netflix, Disney+, Кинопоиск и другие кинотеатры остаются в выборе — режим «ваш экран»: хост входит в свой аккаунт и шарит экран. Plink не обходит DRM и не хранит чужие пароли.',
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
