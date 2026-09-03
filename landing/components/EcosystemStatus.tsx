'use client';

import { motion } from 'framer-motion';
import { ECOSYSTEM_STATUS } from '@/lib/constants';

export default function EcosystemStatus() {
  return (
    <section
      id="ecosystem"
      className="relative border-y border-surface-2 py-16 lg:py-20"
      aria-label="Платформы Plink"
    >
      <div className="container-main">
        <div className="mb-10 flex items-baseline justify-between">
          <span className="section-label">Экосистема</span>
          <span className="font-mono text-[11px] text-text-muted">2026</span>
        </div>

        <div className="grid grid-cols-2 gap-px overflow-hidden rounded-xl bg-surface-2 sm:grid-cols-4">
          {ECOSYSTEM_STATUS.map((item, i) => {
            // «available» — приложение в магазине, «beta» — публичная бета:
            // обе платформы реально можно поставить, остальные ещё в работе.
            const live = item.status === 'available' || item.status === 'beta';
            return (
              <motion.div
                key={item.platform}
                initial={{ opacity: 0, y: 12 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.5, delay: i * 0.08, ease: [0.32, 0.72, 0, 1] }}
                className="group relative bg-bg px-6 py-6"
              >
                <div className="flex items-center gap-2.5">
                  {live ? (
                    <span
                      className={`h-1.5 w-1.5 rounded-full ${
                        item.status === 'available' ? 'bg-accent' : 'border border-accent'
                      }`}
                      aria-hidden="true"
                    />
                  ) : (
                    <span
                      className="h-1.5 w-1.5 rounded-full border border-text-muted"
                      aria-hidden="true"
                    />
                  )}
                  <span className="text-sm font-medium text-text-primary">{item.platform}</span>
                </div>
                <p
                  className={`mt-2 font-mono text-[11px] ${
                    live ? 'text-accent' : 'text-text-muted'
                  }`}
                >
                  {item.note}
                </p>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
