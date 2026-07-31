export const APP_STORE_URL = "https://apps.apple.com/app/plink/id0000000000";
export const SUPPORT_EMAIL = "support@plink.app";

export const COMPARISON_DATA = [
  {
    feature: "Нативное iOS-приложение",
    plink: true,
    rave: true,
    teleparty: false,
    scener: false,
    watch2gether: false,
    discord: true,
  },
  {
    feature: "Без расширения для браузера",
    plink: true,
    rave: true,
    teleparty: false,
    scener: false,
    watch2gether: false,
    discord: false,
  },
  {
    feature: "VK Видео и Rutube",
    plink: true,
    rave: false,
    teleparty: false,
    scener: false,
    watch2gether: false,
    discord: false,
  },
  {
    feature: "Вход по коду / QR",
    plink: true,
    rave: false,
    teleparty: false,
    scener: false,
    watch2gether: true,
    discord: false,
  },
  {
    feature: "Без регистрации у гостей",
    plink: true,
    rave: false,
    teleparty: false,
    scener: false,
    watch2gether: true,
    discord: false,
  },
  {
    feature: "Бесплатные комнаты",
    plink: "Без лимита",
    rave: "Есть",
    teleparty: "Есть",
    scener: "Есть",
    watch2gether: "Есть",
    discord: "Есть",
  },
] as const;

export const FAQ_DATA = [
  {
    q: "Нужно ли всем участникам что-то скачивать?",
    a: "Только организатору. Друзья могут присоединиться по ссылке или QR-коду без установки приложения — для них откроется веб-версия. Но с приложением удобнее: реакции, чат и уведомления работают нативно.",
  },
  {
    q: "Какие видеоплатформы поддерживаются?",
    a: "YouTube, VK Видео и Rutube. Ссылку можно вставить напрямую или найти видео через встроенный поиск.",
  },
  {
    q: "Сколько человек помещается в комнату?",
    a: "До 50 человек в бесплатной версии. Plink+ снимает ограничение.",
  },
  {
    q: "Что происходит, если кто-то ставит на паузу?",
    a: "Видео останавливается у всех одновременно. Это и есть суть синхронного просмотра — общий контроль, общий ритм.",
  },
  {
    q: "Чем Plink+ отличается от бесплатной версии?",
    a: "Plink+ добавляет живые темы оформления комнаты, премиальные реакции и кастомные темы приложения. Основной функционал — комнаты, синхронный просмотр, чат, базовые реакции — остаётся бесплатным навсегда.",
  },
  {
    q: "Как отменить подписку?",
    a: "Настройки → Apple ID → Подписки → Plink. Отмена занимает 10 секунд, доступ сохраняется до конца оплаченного периода.",
  },
  {
    q: "Работает ли на Android?",
    a: "Сейчас Plink доступен только на iOS. Мы сфокусированы на одной платформе, чтобы сделать её безупречно.",
  },
  {
    q: "Нужен ли VPN для иностранных платформ?",
    a: "Plink сам по себе не требует VPN. Но доступность конкретных видео зависит от политик платформ и вашего региона.",
  },
] as const;

export const PRICING = {
  monthly: { price: 299, period: "мес", usd: "$2.99" },
  yearly: { price: 2990, period: "год", usd: "$29.99", monthlyEquivalent: 249 },
} as const;
