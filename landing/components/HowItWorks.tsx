"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";

const steps = [
  {
    num: "01",
    title: "Создай комнату",
    desc: "Назовите её как угодно — от «вечер пятницы» до «разбор трейлера». Plink выдаст короткий код.",
    detail: "K7XQ2M",
  },
  {
    num: "02",
    title: "Отправь код друзьям",
    desc: "Ссылка, QR-код или прямое приглашение онлайн-друзьям. Никаких установок для гостей.",
    detail: "plink.app/join/K7XQ2M",
  },
  {
    num: "03",
    title: "Смотрите вместе",
    desc: "Вставь ссылку на YouTube, VK или Rutube. Все устройства синхронизируются автоматически.",
    detail: "Пауза у одного — пауза у всех",
  },
];

export default function HowItWorks() {
  const containerRef = useRef<HTMLDivElement>(null);
  const prefersReducedMotion = useReducedMotion();

  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ["start end", "end start"],
  });

  const lineHeight = useTransform(scrollYProgress, [0.1, 0.6], ["0%", "100%"]);

  return (
    <section
      ref={containerRef}
      id="how-it-works"
      className="relative py-section-md lg:py-section-lg"
      aria-label="Как это работает"
    >
      <div className="container-main">
        {/* Section header — left aligned, asymmetric */}
        <div className="mb-16 lg:mb-24">
          <span className="section-label mb-4 block">Просто как один-два-три</span>
          <h2 className="text-display max-w-2xl text-3xl text-text-primary sm:text-4xl lg:text-5xl">
            Три касания —<br />и вы уже вместе
          </h2>
        </div>

        <div className="relative">
          {/* Vertical progress line */}
          <div className="absolute left-[19px] top-0 hidden h-full w-px bg-surface-2 md:block lg:left-[23px]">
            <motion.div
              className="w-full bg-accent"
              style={{ height: prefersReducedMotion ? "100%" : lineHeight }}
            />
          </div>

          {/* Steps */}
          <div className="space-y-20 md:space-y-32">
            {steps.map((step, i) => (
              <motion.div
                key={step.num}
                initial={{ opacity: 0, x: -40 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-100px" }}
                transition={{
                  duration: 0.7,
                  delay: prefersReducedMotion ? 0 : i * 0.15,
                  ease: [0.32, 0.72, 0, 1],
                }}
                className="relative grid gap-8 md:grid-cols-12 md:gap-12"
              >
                {/* Step number — offset left */}
                <div className="relative md:col-span-2">
                  <div className="flex h-10 w-10 items-center justify-center rounded-full border-2 border-accent bg-bg text-display text-sm font-bold text-accent md:sticky md:top-32 lg:h-12 lg:w-12 lg:text-base">
                    {step.num}
                  </div>
                </div>

                {/* Content */}
                <div className="md:col-span-7 lg:col-span-6">
                  <h3 className="text-display text-2xl text-text-primary lg:text-3xl">
                    {step.title}
                  </h3>
                  <p className="mt-4 max-w-md text-base leading-relaxed text-text-secondary">
                    {step.desc}
                  </p>
                </div>

                {/* Detail card — floating right, different vertical rhythm */}
                <div className="md:col-span-3 lg:col-span-4">
                  <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    viewport={{ once: true }}
                    transition={{
                      duration: 0.5,
                      delay: prefersReducedMotion ? 0 : 0.3 + i * 0.15,
                      ease: [0.32, 0.72, 0, 1],
                    }}
                    className={`rounded-2xl border border-surface-2 bg-surface p-5 ${
                      i === 1 ? "md:translate-y-8" : i === 2 ? "md:-translate-y-4" : ""
                    }`}
                  >
                    <code className="text-sm font-medium text-accent">{step.detail}</code>
                  </motion.div>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
