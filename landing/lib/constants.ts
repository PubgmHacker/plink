export const APP_STORE_URL = "https://apps.apple.com/app/plink/id0000000000";
export const SUPPORT_EMAIL = "support@plink.app";

// Честный статус платформ — iOS готов, остальные в разработке.
// Никаких фейковых скриншотов под несуществующие клиенты.
export const ECOSYSTEM_STATUS = [
  { platform: "iOS", status: "available" as const, note: "В App Store" },
  { platform: "macOS", status: "development" as const, note: "В разработке" },
  { platform: "Windows", status: "development" as const, note: "В разработке" },
  { platform: "Android", status: "development" as const, note: "В разработке" },
];

export const FAQ_DATA = [
  {
    q: "Нужно ли всем участникам что-то скачивать?",
    a: "Только тому, кто создаёт комнату. Друзья открывают ссылку или сканируking QR-код — и сразу внутри. Расширений и установок не нужно.",
  },
  {
    q: "Какие сервисы поддерживаются?",
    a: "YouTube, VK Видео, Rutube, Кинопоиск, Okko, Wink, Start, Ivi, Premier, Smotrim, Kion, Disney+, Netflix, Prime Video — 14 всего.",
  },
  {
    q: "Что будет, если кто-то нажмёт на паузу?",
    a: "Видео остановится у всех сразу. Синхронно и без задержек — никто не смотрит в одиночку.",
  },
  {
    q: "Что даёт Plink+?",
    a: "Живые темы для комнат, премиальные реакции и кастомные темы для интерфейса. Смотреть вместе, чатиться и делать реакции можно бесплатно.",
  },
  {
    q: "Как отменить подписку?",
    a: "Настройки → Apple ID → Подписки → Plink. Нажмёте «Отменить» — сразу прекратится дебетование, доступ останется до конца оплаченного периода.",
  },
  {
    q: "Будет ли Plink на Mac, Windows, Android?",
    a: "Да, macOS и Windows в активной разработке. Сейчас полностью готов только iOS.",
  },
  {
    q: "Нужен ли VPN для иностранных сервисов?",
    a: "Plink не требует VPN. Но доступный контент зависит от вашего региона — как и в любом легальном сервисе.",
  },
] as const;

export const PRICING = {
  monthly: { price: 299, period: "мес", usd: "$2.99" },
  yearly: { price: 2990, period: "год", usd: "$29.99", monthlyEquivalent: 249 },
} as const;
