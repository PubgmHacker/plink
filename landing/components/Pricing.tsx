'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { PRICING } from '@/lib/constants';
import StoreCta from './StoreCta';

type Period = 'monthly' | 'yearly';

export default function Pricing() {
  const [period, setPeriod] = useState<Period>('yearly');
  const [isAnimating, setIsAnimating] = useState(false);

  const togglePeriod = (p: Period) => {
    if (p === period || isAnimating) return;
    setIsAnimating(true);
    setPeriod(p);
    setTimeout(() => setIsAnimating(false), 300);
  };

  const current = PRICING[period];

  return (
    <section
      id="pricing"
      className="relative border-t border-surface-2 py-24 lg:py-32"
      aria-label="Тарифы"
    >
      <div className="container-main">
        {/* Header */}
        <div className="mb-16">
          <span className="section-label mb-4 block">Тарифы</span>
          <h2 className="text-display text-3xl text-text-primary sm:text-4xl lg:text-5xl">
            Смотрите бесплатно.
            <br />
            Плюс — за персонализацию.
          </h2>
        </div>

        {/* Toggle */}
        <div className="mb-12 flex">
          <div className="liquid-glass relative inline-flex rounded-full p-1">
            <motion.div
              layout
              className="absolute inset-y-1 rounded-lg bg-accent"
              initial={false}
              animate={{
                left: period === 'monthly' ? 4 : '50%',
                right: period === 'monthly' ? '50%' : 4,
              }}
              transition={{ type: 'spring', stiffness: 400, damping: 30 }}
            />
            {(['monthly', 'yearly'] as const).map((p) => (
              <button
                key={p}
                onClick={() => togglePeriod(p)}
                className={`relative z-10 rounded-lg px-6 py-2.5 text-sm font-medium transition-colors focus:outline-none ${
                  period === p ? 'text-bg' : 'text-text-secondary hover:text-text-primary'
                }`}
                aria-pressed={period === p}
              >
                {p === 'monthly' ? 'Помесячно' : 'На год'}
              </button>
            ))}
          </div>
        </div>

        <div className="mx-auto grid max-w-4xl gap-6 lg:grid-cols-2 lg:gap-8">
          {/* Free plan */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, ease: [0.32, 0.72, 0, 1] }}
            className="relative rounded-3xl border border-white/[0.07] bg-white/[0.02] p-8 lg:p-10"
          >
            <h3 className="text-display text-xl font-semibold text-text-primary">Бесплатно</h3>
            <p className="mt-2 text-text-secondary">Для тех, кто просто хочет смотреть вместе</p>

            <div className="mt-8 flex items-baseline gap-2">
              <span className="text-display text-5xl font-bold text-text-primary">0</span>
              <span className="text-lg text-text-secondary">₽</span>
            </div>

            <ul className="mt-8 space-y-4">
              {[
                'Комнаты без ограничений',
                'Синхронный просмотр',
                'Чат и базовые реакции',
                'Друзья и групповые чаты',
                'YouTube, VK Видео, Rutube',
              ].map((item, i) => (
                <li key={i} className="flex items-center gap-3 text-sm text-text-primary">
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    className="shrink-0 text-accent"
                  >
                    <path d="M5 13l4 4L19 7" />
                  </svg>
                  {item}
                </li>
              ))}
            </ul>

            <StoreCta
              label="Скачать бесплатно"
              className="liquid-glass liquid-glass-interactive mt-10 block w-full rounded-full py-4 text-center text-base font-semibold text-text-primary transition-all duration-300 hover:-translate-y-0.5 focus:outline-none focus:ring-2 focus:ring-accent"
            />
          </motion.div>

          {/* Paid plan */}
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.1, ease: [0.32, 0.72, 0, 1] }}
            className="liquid-glass liquid-glass-strong relative rounded-3xl p-8 shadow-[0_28px_80px_-32px_rgb(var(--accent)_/_0.32)] ring-1 ring-accent/25 lg:p-10"
          >
            {/* Тёплая подсветка снизу — платный тариф должен читаться как
                другой уровень, а не как копия бесплатного с другим текстом. */}
            <div
              className="bg-accent/12 pointer-events-none absolute -bottom-24 left-1/2 h-56 w-[78%] -translate-x-1/2 rounded-full blur-[70px]"
              aria-hidden="true"
            />
            <div
              className="absolute inset-x-10 top-0 h-px bg-gradient-to-r from-transparent via-accent to-transparent"
              aria-hidden="true"
            />

            <h3 className="text-display text-xl font-semibold text-text-primary">Plink+</h3>
            <p className="mt-2 text-text-secondary">
              Живые темы, премиальные реакции, кастомизация
            </p>

            {/* Animated price */}
            <div className="mt-8 flex h-16 items-baseline gap-2 overflow-hidden">
              <AnimatePresence mode="wait">
                <motion.div
                  key={period}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -20 }}
                  transition={{ duration: 0.2, ease: [0.32, 0.72, 0, 1] }}
                  className="flex items-baseline gap-2"
                >
                  <span className="font-mono text-5xl font-medium text-accent">
                    {current.price.toLocaleString('ru-RU')}
                  </span>
                  <span className="text-lg text-text-secondary">₽/{current.period}</span>
                </motion.div>
              </AnimatePresence>
            </div>

            {/* Price details */}
            <div className="mt-2 min-h-[24px]">
              <AnimatePresence mode="wait">
                <motion.span
                  key={period}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="text-sm text-text-muted"
                >
                  {period === 'yearly' ? (
                    <>
                      ~{PRICING.yearly.monthlyEquivalent} ₽/мес · {current.usd}
                      <span className="ml-2 rounded-full bg-accent/10 px-2 py-0.5 text-xs text-accent">
                        2 месяца бесплатно
                      </span>
                    </>
                  ) : (
                    <>{current.usd} / месяц</>
                  )}
                </motion.span>
              </AnimatePresence>
            </div>

            <ul className="mt-8 space-y-4">
              {[
                'Всё из бесплатного',
                'Живые темы оформления комнат',
                'Премиальные реакции',
                'Кастомные темы приложения',
              ].map((item, i) => (
                <li key={i} className="flex items-center gap-3 text-sm text-text-primary">
                  <svg
                    width="18"
                    height="18"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    className="shrink-0 text-accent"
                  >
                    <path d="M5 13l4 4L19 7" />
                  </svg>
                  {item}
                </li>
              ))}
            </ul>

            <StoreCta
              label="Оформить Plink+"
              className="mt-10 block w-full rounded-full bg-accent py-4 text-center text-base font-semibold text-bg shadow-[0_12px_38px_-10px_rgb(var(--accent)_/_0.6)] transition-all duration-300 hover:-translate-y-0.5 hover:bg-accent-dim focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 focus:ring-offset-bg"
            />

            <p className="mt-4 text-center text-xs text-text-muted">
              Подписка оформляется в приложении через App Store. Автопродление. Отмена — Настройки →
              Apple ID → Подписки.
            </p>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
