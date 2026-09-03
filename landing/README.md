# Plink — лендинг

Маркетинговый сайт Plink (совместный просмотр видео) на Next.js 16 (App Router),
Tailwind CSS и TypeScript. Язык сайта — русский. Шрифты — Unbounded, Manrope и
JetBrains Mono через `next/font`, загружаются при сборке.

## Запуск

```bash
npm install
npm run dev     # http://localhost:3000
npm run build   # production-сборка
npm run start   # запуск собранного сайта
```

## Проверки перед коммитом

```bash
npm run typecheck     # tsc --noEmit
npm run lint          # eslint
npm run format:check  # prettier (правит: npm run format)
npm run build
```

## Переменные окружения

| Переменная                   | Что делает                            |
| ---------------------------- | ------------------------------------- |
| `NEXT_PUBLIC_APP_STORE_URL`  | Ссылка на приложение в App Store      |
| `NEXT_PUBLIC_TESTFLIGHT_URL` | Ссылка на публичную бету в TestFlight |

Кнопки «Скачать» и статус iOS считаются в `lib/constants.ts` (`getStoreCta()`):

- задана ссылка App Store — кнопки ведут в App Store, подпись «Скачать в App Store»,
  бейдж в hero «Уже в App Store»;
- иначе задана ссылка TestFlight — кнопки ведут в TestFlight, подпись «Открыть в
  TestFlight», бейдж «Бета в TestFlight»;
- ничего не задано — кнопки неактивны (`<span aria-disabled>`) с подписью «Скоро в
  App Store», бейдж и раздел «Экосистема» говорят «Скоро в App Store».

Заглушек-ссылок нет: без переменных сайт честно показывает, что приложения в
магазине ещё нет.

## Бренд

Цвета сайта заданы в одном месте — `:root` в `app/globals.css`; `tailwind.config.ts`
ссылается на эти переменные. Иконки, манифест и og-картинка в `public/` копируются из
`brand/platforms/web/`; знак Plink в вёрстке — `components/PlinkMark.tsx` (цвета
бренда описаны в `brand/README.md`).

## Юридические страницы

Тексты `/terms` и `/privacy` (`app/terms/page.tsx`, `app/privacy/page.tsx`) дублируют
страницы, которые бэкенд отдаёт приложению (`backend/src/web/legal.ts`). Меняя
формулировку, правьте оба места.
