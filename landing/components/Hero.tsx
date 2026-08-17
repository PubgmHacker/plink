'use client';

import { motion, useReducedMotion } from 'framer-motion';
import { APP_STORE_URL } from '@/lib/constants';
import Image from 'next/image';

const screens = [
  { src: '/screens/room-watching.webp', alt: 'Комната — видео, чат, реакции в одном экране' },
  { src: '/screens/room-chat.webp', alt: 'Чат рядом с кадром' },
  { src: '/screens/friends.webp', alt: 'Друзья и онлайн-статус' },
  { src: '/screens/themes.webp', alt: 'Темы оформления' },
] as const;

export default function Hero() {
  const prefersReducedMotion = useReducedMotion();

  return (
    <section className="relative overflow-hidden" aria-label="Plink — совместный просмотр видео">
      {/* Фон: живое видео из приложения, зацикленное. При reduced-motion — статичный кадр. */}
      <div className="absolute inset-0" aria-hidden="true">
        {prefersReducedMotion ? (
          <div
            className="absolute inset-0 bg-cover bg-center"
            style={{ backgroundImage: 'url(/video/hero-poster.jpg)' }}
          />
        ) : (
          <video
            autoPlay
            muted
            loop
            playsInline
            preload="auto"
            poster="/video/hero-poster.jpg"
            className="absolute inset-0 h-full w-full object-cover"
          >
            <source src="/video/hero-loop.mp4" type="video/mp4" />
          </video>
        )}
        {/* Затемнение в три слоя. Один линейный градиент не справлялся:
            заголовок попадал на светлые кадры видео и терял контраст.
            Радиальная вуаль гасит центр под текстом, нижний градиент
            сшивает секцию со следующей. */}
        <div className="absolute inset-0 bg-gradient-to-b from-bg/75 via-bg/60 to-bg" />
        <div className="absolute inset-0 bg-[radial-gradient(75%_55%_at_50%_38%,rgba(10,12,13,0.82),transparent_72%)]" />
        <div className="absolute inset-x-0 bottom-0 h-56 bg-gradient-to-t from-bg to-transparent" />
      </div>

      {/* Весь верх — центр: логика «текст центр → скриншоты внизу», как rave.io */}
      <div className="relative z-10 flex min-h-[92vh] flex-col items-center justify-center px-6 pt-24 text-center">
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: [0.32, 0.72, 0, 1] }}
          className="max-w-3xl"
        >
          {/* Раньше здесь стояли четыре равных бейджа iOS/macOS/Windows/Android,
              хотя готов только iOS. Теперь заявлено ровно то, что есть. */}
          <div className="mb-7 flex items-center justify-center">
            <span className="liquid-glass inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-[11px] font-medium uppercase tracking-[0.18em] text-text-muted">
              <span className="relative flex h-1.5 w-1.5">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-accent opacity-70" />
                <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-accent" />
              </span>
              Уже в App Store
            </span>
          </div>

          <h1 className="text-display text-4xl leading-[1.08] text-text-primary sm:text-5xl lg:text-6xl">
            Один кадр.
            <br />
            <span className="text-accent">Одна пауза.</span>
            <br />
            Одна комната.
          </h1>

          <p className="mx-auto mt-7 max-w-xl text-[16px] leading-relaxed text-text-secondary">
            Смотрите фильмы и сериалы с друзьями. На паузу нажал один — у всех встало. Работает на
            YouTube, VK Видео, Rutube и ещё одиннадцати сервисах.
          </p>

          <div className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="group inline-flex items-center gap-2.5 rounded-full bg-accent px-8 py-4 text-[15px] font-semibold text-bg shadow-[0_10px_36px_-8px_rgba(255,184,0,0.55)] transition-all duration-300 hover:-translate-y-0.5 hover:bg-accent-dim hover:shadow-[0_16px_44px_-10px_rgba(255,184,0,0.65)] focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 focus:ring-offset-bg"
            >
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-.81 3.19-.51.87-1.63 1.82-2.68 1.78-.13-1.19.33-2.42.55-3.47z" />
              </svg>
              Скачать в App Store
            </a>
            <a
              href="#how-it-works"
              className="liquid-glass liquid-glass-interactive inline-flex items-center gap-2 rounded-full px-7 py-4 text-[15px] font-medium text-text-primary transition-transform duration-300 hover:-translate-y-0.5 focus:outline-none focus:ring-2 focus:ring-accent"
            >
              Как это работает
              <span
                aria-hidden="true"
                className="transition-transform duration-300 group-hover:translate-x-0.5"
              >
                →
              </span>
            </a>
          </div>

          <div className="mt-8 flex items-center justify-center gap-3">
            <span className="text-[11px] uppercase tracking-wider text-text-muted">
              Пример комнаты
            </span>
            <code className="font-mono text-sm font-medium tracking-[0.22em] text-accent">
              K7XQ2M
            </code>
          </div>
        </motion.div>

        {/* Полка из четырёх реальных скриншотов — как у конкурентов, но без вранья */}
        <motion.div
          className="mt-14 grid w-full max-w-5xl grid-cols-2 gap-4 sm:grid-cols-4 sm:gap-6"
          initial={{ opacity: 0, y: 32 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.25, ease: [0.32, 0.72, 0, 1] }}
        >
          {screens.map((s, i) => (
            <motion.figure
              key={s.src}
              className="group"
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.6,
                delay: 0.35 + i * 0.07,
                ease: [0.32, 0.72, 0, 1],
              }}
            >
              <div
                className="relative overflow-hidden rounded-2xl border border-white/10 bg-black/40"
                style={{ aspectRatio: '402/874' }}
              >
                <Image
                  src={s.src}
                  alt={s.alt}
                  fill
                  priority={i === 0}
                  sizes="(max-width: 640px) 45vw, 220px"
                  className="object-cover"
                />
              </div>
              <figcaption className="mt-2.5 text-[11px] font-medium uppercase tracking-[0.14em] text-text-muted">
                {s.alt.split(' — ')[0]}
              </figcaption>
            </motion.figure>
          ))}
        </motion.div>
      </div>

      {/* Scroll hint */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.2, duration: 0.6 }}
        className="absolute bottom-7 left-1/2 z-10 -translate-x-1/2"
        aria-hidden="true"
      >
        <div className="flex flex-col items-center gap-2 text-text-muted">
          <span className="text-[11px]">Листай</span>
          <div className="h-8 w-px bg-text-muted" />
        </div>
      </motion.div>
    </section>
  );
}
