// i18n structure — ready for ru/en. Currently Russian is default.
// Future: use next-intl or next-i18next for full SSR translation.

export type Locale = "ru" | "en";

export const locales: Locale[] = ["ru", "en"];
export const defaultLocale: Locale = "ru";

export const messages: Record<Locale, Record<string, string>> = {
  ru: {
    "nav.how": "Как работает",
    "nav.features": "Возможности",
    "nav.ecosystem": "Экосистема",
    "nav.pricing": "Тарифы",
    "nav.faq": "FAQ",
    "nav.download": "Скачать",
    "hero.label.ios": "iOS",
    "hero.label.free": "Бесплатно",
    "hero.title": "Один кадр.",
    "hero.subtitle":
      "Зовёшь друзей по ссылке — и смотрите фильм вместе, каждый у себя. Кто-то нажал паузу — видео встало у всех.",
    "hero.code.label": "Код комнаты",
    "hero.code.copy": "Копировать",
    "hero.cta.download": "Скачать в App Store",
    "hero.cta.ecosystem": "Другие платформы",
    "ecosystem.section": "Экосистема",
    "how.section": "Просто как один-два-три",
    "how.title": "Три касания — и вы уже вместе",
    "how.step1.title": "Открой и нажми «Смотреть с друзьями»",
    "how.step1.desc":
      "Назови комнату — от «фильмы на пятницу» до «трейлер в час ночи». Получишь короткий код, который покажешь друзьям.",
    "how.step1.detail": "K7XQ2M",
    "how.step2.title": "Скинь ссылку в чат",
    "how.step2.desc":
      "Друзья кликают и попадают в комнату — телефон, планшет или ноутбук, ничего не нужно ставить.",
    "how.step2.detail": "plink.app/join/K7XQ2M",
    "how.step3.title": "Выберите что смотреть",
    "how.step3.desc":
      "YouTube, VK Видео, Rutube и ещё одиннадцать сервисов. Вставьте ссылку или найдите через поиск — начнётся у всех.",
    "how.step3.detail": "Один начал — смотрите все",
    "features.section": "Что внутри",
    "features.title": "Друзья видеорядом с кадром",
    "features.subtitle": "Ни один скриншот не отфотошоплен — всё снято с самого приложения, как есть.",
    "platforms.section": "Источники",
    "platforms.title": "Откуда смотреть",
    "pricing.section": "Тарифы",
    "pricing.title": "Смотреть — бесплатно. Оформлять комнату — по желанию.",
    "faq.section": "Вопросы и ответы",
    "faq.title": "Что спрашивают чаще всего",
    "cta.code.label": "Пример кода:",
    "cta.title": "Создайте комнату. Позовите друзей.",
    "cta.subtitle": "Бесплатно. Без регистрации для гостей.",
    "footer.rights": "Все права защищены.",
  },
  en: {
    "nav.how": "How it works",
    "nav.features": "Features",
    "nav.ecosystem": "Ecosystem",
    "nav.pricing": "Pricing",
    "nav.faq": "FAQ",
    "nav.download": "Download",
    "hero.label.ios": "iOS",
    "hero.label.free": "Free",
    "hero.title": "One frame.",
    "hero.subtitle":
      "Watch YouTube, VK Video and Rutube in sync with friends. One progress bar, one moment, wherever you are.",
    "hero.code.label": "Room code",
    "hero.code.copy": "Copy",
    "hero.cta.download": "Download on App Store",
    "hero.cta.ecosystem": "Other platforms",
    "ecosystem.section": "Ecosystem",
    "how.section": "As simple as one-two-three",
    "how.title": "Three taps — and you're together",
    "how.step1.title": "Create a room",
    "how.step1.desc":
      "Name it anything — from «Friday night» to «trailer breakdown». Plink gives you a short code.",
    "how.step1.detail": "K7XQ2M",
    "how.step2.title": "Send the code",
    "how.step2.desc":
      "Link, QR code, or direct invite to online friends. No installs required for guests.",
    "how.step2.detail": "plink.app/join/K7XQ2M",
    "how.step3.title": "Watch together",
    "how.step3.desc":
      "Paste a YouTube, VK or Rutube link. All devices sync automatically.",
    "how.step3.detail": "One pauses — everyone pauses",
    "features.section": "What's inside",
    "features.title": "A real interface, not a mockup",
    "features.subtitle": "Every screen here is a frame from the actual app, unretouched.",
    "platforms.section": "Sources",
    "platforms.title": "Where to watch from",
    "pricing.section": "Pricing",
    "pricing.title": "Watching is free. Decorating your room is optional.",
    "faq.section": "Q&A",
    "faq.title": "Frequently asked questions",
    "cta.code.label": "Example code:",
    "cta.title": "Create a room. Invite friends.",
    "cta.subtitle": "Free. No registration for guests.",
    "footer.rights": "All rights reserved.",
  },
};

export function t(key: string, locale: Locale = defaultLocale): string {
  return messages[locale]?.[key] ?? messages[defaultLocale][key] ?? key;
}
