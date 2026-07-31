// i18n structure — ready for ru/en. Currently Russian is default.
// Future: use next-intl or next-i18next for full SSR translation.

export type Locale = "ru" | "en";

export const locales: Locale[] = ["ru", "en"];
export const defaultLocale: Locale = "ru";

export const messages: Record<Locale, Record<string, string>> = {
  ru: {
    "nav.how": "Как работает",
    "nav.features": "Возможности",
    "nav.comparison": "Сравнение",
    "nav.pricing": "Тарифы",
    "nav.faq": "FAQ",
    "nav.download": "Скачать",
    "hero.label.ios": "iOS",
    "hero.label.free": "Бесплатно",
    "hero.title.line1": "Один кадр.",
    "hero.title.line2": "Одна пауза.",
    "hero.title.line3": "Одна комната.",
    "hero.subtitle":
      "Смотри YouTube, VK Видео и Rutube синхронно с друзьями. Создай комнату, отправь код — и смотрите вместе, где бы вы ни были.",
    "hero.code.label": "Код комнаты",
    "hero.code.copy": "Копировать",
    "hero.cta.download": "Скачать в App Store",
    "hero.cta.how": "Как это работает",
    "how.section": "Просто как один-два-три",
    "how.title": "Три касания — и вы уже вместе",
    "how.step1.title": "Создай комнату",
    "how.step1.desc":
      "Назовите её как угодно — от «вечер пятницы» до «разбор трейлера». Plink выдаст короткий код.",
    "how.step1.detail": "K7XQ2M",
    "how.step2.title": "Отправь код друзьям",
    "how.step2.desc":
      "Ссылка, QR-код или прямое приглашение онлайн-друзьям. Никаких установок для гостей.",
    "how.step2.detail": "plink.app/join/K7XQ2M",
    "how.step3.title": "Смотрите вместе",
    "how.step3.desc":
      "Вставь ссылку на YouTube, VK или Rutube. Все устройства синхронизируются автоматически.",
    "how.step3.detail": "Пауза у одного — пауза у всех",
    "features.section": "Что внутри",
    "features.title.line1": "Не список функций —",
    "features.title.line2": "способы быть ближе",
    "features.subtitle":
      "Мы убрали всё лишнее, чтобы осталось главное: видео, друзья, общий момент.",
    "platforms.section": "Источники",
    "platforms.title.line1": "Три платформы.",
    "platforms.title.line2": "Бесконечный контент.",
    "comparison.section": "Честное сравнение",
    "comparison.title.line1": "Не единственные.",
    "comparison.title.line2": "Но единственные такие.",
    "pricing.section": "Просто и честно",
    "pricing.title.line1": "Бесплатно — по-настоящему.",
    "pricing.title.line2": "Плюс — по желанию.",
    "faq.section": "Вопросы и ответы",
    "faq.title": "Что спрашивают чаще всего",
    "cta.code.label": "Твой код комнаты:",
    "cta.title.line1": "Создай комнату.",
    "cta.title.line2": "Позови друзей.",
    "cta.subtitle":
      "Бесплатно. Без регистрации для гостей. Работает там, где вы уже смотрите видео.",
    "footer.rights": "Все права защищены.",
    "footer.made": "Сделано с любовью к совместным просмотрам",
  },
  en: {
    "nav.how": "How it works",
    "nav.features": "Features",
    "nav.comparison": "Compare",
    "nav.pricing": "Pricing",
    "nav.faq": "FAQ",
    "nav.download": "Download",
    "hero.label.ios": "iOS",
    "hero.label.free": "Free",
    "hero.title.line1": "One frame.",
    "hero.title.line2": "One pause.",
    "hero.title.line3": "One room.",
    "hero.subtitle":
      "Watch YouTube, VK Video and Rutube in sync with friends. Create a room, send the code — and watch together, wherever you are.",
    "hero.code.label": "Room code",
    "hero.code.copy": "Copy",
    "hero.cta.download": "Download on App Store",
    "hero.cta.how": "How it works",
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
    "features.title.line1": "Not a feature list —",
    "features.title.line2": "ways to feel closer",
    "features.subtitle":
      "We removed everything unnecessary. What remains: video, friends, the shared moment.",
    "platforms.section": "Sources",
    "platforms.title.line1": "Three platforms.",
    "platforms.title.line2": "Endless content.",
    "comparison.section": "Honest comparison",
    "comparison.title.line1": "Not the only ones.",
    "comparison.title.line2": "But the only ones like this.",
    "pricing.section": "Simple and honest",
    "pricing.title.line1": "Free — for real.",
    "pricing.title.line2": "Plus — if you want more.",
    "faq.section": "Q&A",
    "faq.title": "Frequently asked questions",
    "cta.code.label": "Your room code:",
    "cta.title.line1": "Create a room.",
    "cta.title.line2": "Invite friends.",
    "cta.subtitle":
      "Free. No registration for guests. Works where you already watch videos.",
    "footer.rights": "All rights reserved.",
    "footer.made": "Made with love for shared viewing",
  },
};

export function t(key: string, locale: Locale = defaultLocale): string {
  return messages[locale]?.[key] ?? messages[defaultLocale][key] ?? key;
}
