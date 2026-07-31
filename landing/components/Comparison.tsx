"use client";

import { motion } from "framer-motion";
import { COMPARISON_DATA } from "@/lib/constants";

const competitors = [
  { key: "plink", name: "Plink", highlight: true },
  { key: "rave", name: "Rave" },
  { key: "teleparty", name: "Teleparty" },
  { key: "scener", name: "Scener" },
  { key: "watch2gether", name: "Watch2Gether" },
  { key: "discord", name: "Discord" },
];

export default function Comparison() {
  return (
    <section
      id="comparison"
      className="relative py-section-md lg:py-section-lg"
      aria-label="Сравнение с конкурентами"
    >
      <div className="absolute inset-0 bg-surface/20" />

      <div className="container-main relative">
        {/* Header */}
        <div className="mb-16 max-w-2xl">
          <span className="section-label mb-4 block">Честное сравнение</span>
          <h2 className="text-display text-3xl text-text-primary sm:text-4xl lg:text-5xl">
            Не единственные.<br />
            <span className="text-accent">Но единственные такие.</span>
          </h2>
          <p className="mt-6 text-text-secondary">
            Мы уважаем конкурентов — они проложили путь. Но у каждого есть компромиссы.
            Вот как выглядит выбор без маркетинговых украшений.
          </p>
        </div>

        {/* Desktop table */}
        <div className="hidden overflow-hidden rounded-2xl border border-surface-2 lg:block">
          <table className="w-full">
            <thead>
              <tr className="border-b border-surface-2 bg-surface">
                <th className="p-5 text-left text-sm font-medium text-text-secondary">
                  Критерий
                </th>
                {competitors.map((c) => (
                  <th
                    key={c.key}
                    className={`p-5 text-center text-sm font-semibold ${
                      c.highlight ? "text-accent" : "text-text-primary"
                    }`}
                  >
                    {c.name}
                    {c.highlight && (
                      <span className="ml-2 rounded-full bg-accent/10 px-2 py-0.5 text-[10px] font-medium text-accent">
                        Мы
                      </span>
                    )}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {COMPARISON_DATA.map((row, i) => (
                <motion.tr
                  key={row.feature}
                  initial={{ opacity: 0, x: -20 }}
                  whileInView={{ opacity: 1, x: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.4, delay: i * 0.05 }}
                  className={`border-b border-surface-2/50 transition-colors hover:bg-surface/50 ${
                    i % 2 === 0 ? "bg-transparent" : "bg-surface/30"
                  }`}
                >
                  <td className="p-5 text-sm text-text-primary">{row.feature}</td>
                  {competitors.map((c) => {
                    const val = row[c.key as keyof typeof row];
                    return (
                      <td key={c.key} className="p-5 text-center">
                        <ComparisonValue value={val} highlight={c.highlight} />
                      </td>
                    );
                  })}
                </motion.tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Mobile cards */}
        <div className="space-y-6 lg:hidden">
          {COMPARISON_DATA.map((row, i) => (
            <motion.div
              key={row.feature}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: i * 0.08 }}
              className="rounded-2xl border border-surface-2 bg-surface p-5"
            >
              <h3 className="text-sm font-semibold text-text-primary">{row.feature}</h3>
              <div className="mt-4 space-y-3">
                {competitors.map((c) => {
                  const val = row[c.key as keyof typeof row];
                  return (
                    <div key={c.key} className="flex items-center justify-between">
                      <span className={`text-sm ${c.highlight ? "font-medium text-accent" : "text-text-secondary"}`}>
                        {c.name}
                      </span>
                      <ComparisonValue value={val} highlight={c.highlight} compact />
                    </div>
                  );
                })}
              </div>
            </motion.div>
          ))}
        </div>

        <p className="mt-8 text-center text-xs text-text-muted lg:text-left">
          Данные актуальны на лето 2026. Возможности могут меняться — проверяйте на сайтах сервисов.
        </p>
      </div>
    </section>
  );
}

function ComparisonValue({
  value,
  highlight,
  compact = false,
}: {
  value: boolean | string;
  highlight?: boolean;
  compact?: boolean;
}) {
  const size = compact ? "h-6 w-6" : "h-8 w-8";
  const iconSize = compact ? 14 : 18;

  if (value === true) {
    return (
      <span
        className={`inline-flex items-center justify-center rounded-full ${size} ${
          highlight ? "bg-accent text-bg" : "bg-surface-2 text-accent"
        }`}
        data-value="yes"
      >
        <svg width={iconSize} height={iconSize} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" aria-hidden="true">
          <path d="M5 13l4 4L19 7" />
        </svg>
        <span className="sr-only">Да</span>
      </span>
    );
  }
  if (value === false) {
    return (
      <span
        className={`inline-flex items-center justify-center rounded-full ${size} bg-surface-2/50 text-text-muted`}
        data-value="no"
      >
        <svg width={compact ? 12 : 16} height={compact ? 12 : 16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
          <path d="M6 18L18 6M6 6l12 12" />
        </svg>
        <span className="sr-only">Нет</span>
      </span>
    );
  }
  return (
    <span className={`text-sm ${highlight ? "font-medium text-accent" : "text-text-secondary"}`}>
      {value}
    </span>
  );
}
