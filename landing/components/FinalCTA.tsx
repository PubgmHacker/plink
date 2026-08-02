"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { APP_STORE_URL } from "@/lib/constants";

export default function FinalCTA() {
  const [copied, setCopied] = useState(false);

  const copyCode = async () => {
    await navigator.clipboard.writeText("K7XQ2M");
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section
      className="relative overflow-hidden border-t border-surface-2 py-28 lg:py-40"
      aria-label="Скачать Plink"
    >
      <div className="absolute inset-0" aria-hidden="true">
        <div className="absolute left-1/2 top-1/2 h-[700px] w-[700px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent/[0.03] blur-[150px]" />
      </div>

      <div className="container-main relative">
        <div className="mx-auto max-w-2xl text-center">
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            whileInView={{ opacity: 1, scale: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, ease: [0.32, 0.72, 0, 1] }}
            className="mb-8 inline-flex items-center gap-3 rounded-xl border border-surface-2 bg-surface px-5 py-3.5"
          >
            <span className="text-xs text-[#B0B7B3]">Пример кода:</span>
            <code className="font-mono text-xl font-medium tracking-[0.2em] text-accent">
              K7XQ2M
            </code>
            <button
              onClick={copyCode}
              className="rounded bg-surface-2 px-2.5 py-1 text-[11px] font-medium text-text-secondary transition-all hover:bg-accent hover:text-bg focus:outline-none focus:ring-2 focus:ring-accent"
              aria-live="polite"
            >
              {copied ? "Скопировано" : "Копировать"}
            </button>
          </motion.div>

          <motion.h2
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.7, delay: 0.1, ease: [0.32, 0.72, 0, 1] }}
            className="text-display text-4xl text-text-primary sm:text-5xl lg:text-6xl"
          >
            Создайте комнату.
            <br />
            Позовите друзей.
          </motion.h2>

          <motion.p
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.2, ease: [0.32, 0.72, 0, 1] }}
            className="mx-auto mt-6 max-w-md text-text-secondary"
          >
            Бесплатно. Без регистрации для гостей.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.3, ease: [0.32, 0.72, 0, 1] }}
            className="mt-10 flex flex-col items-center gap-4 sm:flex-row sm:justify-center"
          >
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-3 rounded-lg bg-accent px-8 py-4 text-lg font-semibold text-bg transition-all duration-300 hover:bg-accent-dim focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 focus:ring-offset-bg"
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-.81 3.19-.51.87-1.63 1.82-2.68 1.78-.13-1.19.33-2.42.55-3.47z" />
              </svg>
              Скачать в App Store
            </a>
            <span className="text-sm text-[#B0B7B3]">iOS 16+</span>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
