"use client";

import { motion } from "framer-motion";

const platforms = [
  {
    name: "YouTube",
    description: "Миллионы видео, музыка, стримы",
    icon: (
      <svg viewBox="0 0 24 24" fill="currentColor" className="h-10 w-10">
        <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
      </svg>
    ),
  },
  {
    name: "VK Видео",
    description: "Русскоязычный контент, сериалы, клипы",
    icon: (
      <svg viewBox="0 0 24 24" fill="currentColor" className="h-10 w-10">
        <path d="M13.162 18.994c.609 0 .858-.406.851-.915-.031-1.917.714-2.949 2.059-1.604 1.488 1.488 1.796 2.519 3.603 2.519h3.2c.808 0 1.126-.26 1.126-.668 0-.863-1.421-2.386-2.625-3.504-1.686-1.565-1.765-1.602-.313-3.486 1.801-2.339 4.157-5.336 2.073-5.336h-3.981c-.772 0-.828.435-1.103 1.366-.995 2.388-1.805 5.283-3.337 5.283-.508 0-.741-.326-.741-1.07V6.494c0-.954.236-1.494-.716-1.494h-4.68c-.508 0-.805.354-.805.744 0 .781.78.961.859 3.155v4.72c0 1.050-.203 1.253-.65 1.253-1.479 0-5.08-4.221-7.235-9.112-.432-1.002-.864-1.411-1.678-1.411H.4c-.451 0-.541.326-.541.744 0 .714.508 3.617 2.362 7.987 2.506 5.91 6.016 9.114 9.894 9.114z" />
      </svg>
    ),
  },
  {
    name: "Rutube",
    description: "Фильмы, шоу, эксклюзивы",
    icon: (
      <svg viewBox="0 0 24 24" fill="currentColor" className="h-10 w-10">
        <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.568 15.568H6.432V8.432h11.136v7.136zM9.818 9.818v4.364l3.818-2.182-3.818-2.182z" />
      </svg>
    ),
  },
];

export default function Platforms() {
  return (
    <section id="platforms" className="relative py-section-md" aria-label="Поддерживаемые платформы">
      <div className="container-main">
        <div className="mb-16 text-center lg:text-left">
          <span className="section-label mb-4 block">Источники</span>
          <h2 className="text-display text-3xl text-text-primary sm:text-4xl">
            Три платформы.<br className="hidden sm:block" />
            <span className="text-text-secondary">Бесконечный контент.</span>
          </h2>
        </div>

        <div className="grid gap-4 sm:grid-cols-3 lg:gap-6">
          {platforms.map((platform, i) => (
            <motion.div
              key={platform.name}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.1, ease: [0.32, 0.72, 0, 1] }}
              className="group relative overflow-hidden rounded-2xl border border-surface-2 bg-surface p-8 text-center transition-colors hover:border-accent/30 sm:text-left"
            >
              <div className="mb-6 inline-flex rounded-xl bg-surface-2 p-3 text-text-primary transition-colors group-hover:text-accent">
                {platform.icon}
              </div>
              <h3 className="text-display text-lg font-semibold text-text-primary">
                {platform.name}
              </h3>
              <p className="mt-2 text-sm text-text-secondary">{platform.description}</p>

              {/* Hover glow */}
              <div className="pointer-events-none absolute -bottom-20 -right-20 h-40 w-40 rounded-full bg-accent/10 opacity-0 blur-3xl transition-opacity duration-500 group-hover:opacity-100" />
            </motion.div>
          ))}
        </div>

        <p className="mt-10 text-center text-sm text-text-muted sm:text-left">
          Просто вставьте ссылку — Plink загрузит видео для всех участников комнаты.
        </p>
      </div>
    </section>
  );
}
