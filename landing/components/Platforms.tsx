"use client";

import { motion } from "framer-motion";

// Реальные платформы из приложения (Assets.xcassets + code inspection, 14 всего)
const platforms = [
  "YouTube", "VK Видео", "Rutube", "Кинопоиск",
  "Okko", "Wink", "Start", "Ivi",
  "Premier", "Smotrim", "Kion", "Disney+",
  "Netflix", "Prime Video",
];

export default function Platforms() {
  return (
    <section id="platforms" className="relative border-t border-surface-2 py-16 lg:py-24" aria-label="Поддерживаемые платформы">
      <div className="container-main">
        {/* Два уровня входа, не центрирование всего подряд */}
        <div className="mb-12 grid gap-10 lg:grid-cols-12 lg:items-end">
          <div className="lg:col-span-7">
            <span className="section-label mb-4 block">Источники</span>
            <h2 className="text-display text-3xl text-text-primary sm:text-4xl">
              Что смотрите — там и есть Plink.
            </h2>
          </div>
          <div className="lg:col-span-4 lg:col-start-9">
            <p className="max-w-md text-sm leading-relaxed text-[#B0B7B3]">
              Найдите контент встроенным поиском или вставьте ссылку — плеер подхватит сам.
            </p>
          </div>
        </div>

        {/* Monochrome wordmark-grid. Плёнка, не иконки в кружках */}
        <div className="flex flex-wrap items-baseline gap-x-10 gap-y-5 sm:gap-x-14">
          {platforms.map((platform, i) => (
            <motion.span
              key={platform}
              initial={{ opacity: 0, y: 10 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: i * 0.03, ease: [0.32, 0.72, 0, 1] }}
              className="group cursor-default text-[17px] font-normal text-[#B0B7B3] transition-colors duration-200 hover:text-text-primary"
            >
              {platform}
              <span className="mx-2 inline-block h-2 w-2 rounded-full bg-surface-2 opacity-0 transition-opacity group-hover:opacity-100" />
            </motion.span>
          ))}
        </div>
      </div>
    </section>
  );
}
