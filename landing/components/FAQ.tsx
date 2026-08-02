"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { FAQ_DATA } from "@/lib/constants";

export default function FAQ() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  return (
    <section
      id="faq"
      className="relative py-24 lg:py-32"
      aria-label="Частые вопросы"
    >
      <div className="container-main">
        <div className="grid gap-16 lg:grid-cols-12">
          {/* Left column — sticky header */}
          <div className="lg:col-span-4">
            <div className="lg:sticky lg:top-32">
              <span className="section-label mb-4 block">Вопросы и ответы</span>
              <h2 className="text-display text-3xl text-text-primary sm:text-4xl">
                Что спрашивают<br />чаще всего
              </h2>
              <p className="mt-6 text-text-secondary">
                Не нашли ответ? Напишите нам —{" "}
                <a
                  href="mailto:support@plink.app"
                  className="text-accent underline decoration-accent/30 underline-offset-4 transition-colors hover:decoration-accent focus:outline-none focus:ring-2 focus:ring-accent"
                >
                  support@plink.app
                </a>
              </p>
            </div>
          </div>

          {/* Right column — accordion */}
          <div className="lg:col-span-8">
            <div className="space-y-4">
              {FAQ_DATA.map((item, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: i * 0.05 }}
                >
                  <button
                    onClick={() => setOpenIndex(openIndex === i ? null : i)}
                    aria-expanded={openIndex === i}
                    aria-controls={`faq-answer-${i}`}
                    className={`group w-full rounded-2xl border text-left transition-all duration-300 focus:outline-none focus:ring-2 focus:ring-accent ${
                      openIndex === i
                        ? "border-accent/50 bg-surface"
                        : "border-surface-2 bg-transparent hover:border-text-muted/50"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4 p-6">
                      <span
                        className={`text-base font-medium transition-colors ${
                          openIndex === i ? "text-accent" : "text-text-primary"
                        }`}
                      >
                        {item.q}
                      </span>
                      <motion.span
                        animate={{ rotate: openIndex === i ? 45 : 0 }}
                        transition={{ duration: 0.3, ease: [0.32, 0.72, 0, 1] }}
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-2 text-text-secondary transition-colors group-hover:bg-accent group-hover:text-bg"
                      >
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <path d="M12 5v14M5 12h14" />
                        </svg>
                      </motion.span>
                    </div>

                    <AnimatePresence>
                      {openIndex === i && (
                        <motion.div
                          id={`faq-answer-${i}`}
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: "auto", opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          transition={{ duration: 0.3, ease: [0.32, 0.72, 0, 1] }}
                          className="overflow-hidden"
                        >
                          <p className="border-t border-surface-2/50 px-6 pb-6 pt-4 text-text-secondary">
                            {item.a}
                          </p>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </button>
                </motion.div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
