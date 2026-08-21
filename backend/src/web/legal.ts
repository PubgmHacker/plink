/// The legal pages the app links to from the paywall and from Settings.
///
/// Why they live here rather than in `landing/`: the iOS binary must link to a
/// URL that resolves today. `landing/` has no deploy configuration, so its
/// `/terms` and `/privacy` exist only as source, and `plink.app` does not serve
/// the app. The backend is the one origin the app already reaches on every
/// request (`PlinkConfig.baseURLString`), so serving the documents from here
/// makes the links work without waiting on DNS or a marketing-site deploy.
/// App Review 3.1.2 rejects a subscription app whose Terms and Privacy links
/// are dead, which is what makes this a release requirement rather than polish.
///
/// `landing/app/{terms,privacy}/page.tsx` hold a marketing-site copy of the
/// same text. This file is canonical: if the two disagree, this one is what the
/// app shows, and the landing copy is what needs correcting.
///
/// The text is Russian because it is user-facing output — see ADR-0001.

/// Where users are told to write. One constant because the address is wrong
/// today: `plink.app` publishes a null MX record (`0 .`, RFC 7505), meaning the
/// domain declares that it accepts no mail at all, so anything sent to
/// `support@plink.app` is rejected by design. Changing the contact channel is
/// the owner's call; keeping it in one place makes that change one line here
/// instead of a search across two languages.
export const SUPPORT_EMAIL = 'support@plink.app';

export interface LegalSection {
  /// Numbered heading, without the number — the renderer adds it.
  heading: string;
  /// Plain text. Escaped on render, so no markup here.
  body: string;
  /// When set, the address is appended to the section as a mailto link.
  email?: string;
}

export interface LegalDocument {
  slug: 'terms' | 'privacy';
  /// <title> and OG title.
  title: string;
  /// <h1>.
  heading: string;
  /// Meta description.
  description: string;
  /// Human-readable date of the last substantive change to the text.
  updated: string;
  sections: LegalSection[];
}

export const TERMS: LegalDocument = {
  slug: 'terms',
  title: 'Условия использования — Plink',
  heading: 'Условия использования',
  description: 'Условия использования сервиса Plink.',
  updated: '30 июля 2026',
  sections: [
    {
      heading: 'Общие положения',
      body:
        'Plink («Сервис») предоставляет программное обеспечение для совместного просмотра ' +
        'видеоконтента. Используя Сервис, вы соглашаетесь с настоящими Условиями.',
    },
    {
      heading: 'Использование сервиса',
      body:
        'Сервис предназначен для личного некоммерческого использования. Вы обязуетесь не ' +
        'использовать Сервис для распространения контента, нарушающего авторские права или ' +
        'законодательство вашей юрисдикции.',
    },
    {
      heading: 'Сторонние видеосервисы',
      body:
        'Plink синхронизирует воспроизведение для YouTube, VK Видео, Rutube и прямых ссылок на ' +
        'медиафайлы — через официальные плееры этих платформ. Для сервисов по подписке доступен ' +
        'режим «смотрим рядом»: вы входите в свой собственный аккаунт, а остальные участники ' +
        'видят экран. Plink не обходит защиту контента, не извлекает и не проксирует защищённые ' +
        'потоки. Доступность любой платформы зависит от неё самой, и Сервис не отвечает за ' +
        'изменения в её работе.',
    },
    {
      heading: 'Подписка Plink+',
      body:
        'Plink+ — дополнительная подписка с расширенными функциями. Доступные периоды и цены ' +
        'показаны на экране покупки. В приложении оплата производится через App Store: подписка ' +
        'продлевается автоматически, если не отменена минимум за 24 часа до окончания текущего ' +
        'периода, отменить её можно в настройках Apple ID. Если предложен бесплатный пробный ' +
        'период, его неиспользованная часть сгорает при покупке подписки. На сайте оплата ' +
        'проходит через ЮKassa: это разовый платёж на выбранный срок, автосписаний нет, ' +
        'продление вручную.',
    },
    {
      heading: 'Ответственность',
      body:
        'Сервис предоставляется «как есть». Мы не несём ответственности за содержание, ' +
        'загружаемое пользователями, и за перебои в работе сторонних видеоплатформ.',
    },
    {
      heading: 'Контакты',
      body: 'По вопросам, связанным с настоящими Условиями, обращайтесь:',
      email: SUPPORT_EMAIL,
    },
  ],
};

export const PRIVACY: LegalDocument = {
  slug: 'privacy',
  title: 'Конфиденциальность — Plink',
  heading: 'Политика конфиденциальности',
  description: 'Политика конфиденциальности Plink.',
  updated: '30 июля 2026',
  sections: [
    {
      heading: 'Какие данные мы собираем',
      body:
        'Аккаунт: email, имя пользователя, аватар (опционально). Контент: история комнат, ' +
        'сообщения чата, реакции. Технические данные: модель устройства, версия ОС, анонимная ' +
        'статистика использования и измерения рассинхрона воспроизведения.',
    },
    {
      heading: 'Как мы используем данные',
      body:
        'Для работы Сервиса: синхронизация комнат, доставка сообщений, персонализация. Для ' +
        'улучшения: анализ сбоев, оптимизация производительности. Мы не продаём ваши данные ' +
        'третьим лицам.',
    },
    {
      heading: 'Хранение',
      body: 'Данные хранятся на серверах в ЕС. Сообщения чата — 30 дней, история комнат — 90 дней.',
    },
    {
      heading: 'Cookies и аналитика',
      body:
        'Веб-версия использует только технические cookies, необходимые для работы. Аналитика ' +
        'анонимизирована и не содержит персональных данных.',
    },
    {
      heading: 'Ваши права',
      body:
        'Удалить аккаунт можно прямо в приложении: «Профиль» → «Удалить аккаунт». Удаление ' +
        'уходит на сервер и выполняется после 14-дневного периода на отмену, после чего данные ' +
        'аккаунта удаляются или анонимизируются. Вы также вправе запросить копию своих данных ' +
        'или их исправление — напишите нам:',
      email: SUPPORT_EMAIL,
    },
  ],
};

export const LEGAL_DOCUMENTS: LegalDocument[] = [TERMS, PRIVACY];
