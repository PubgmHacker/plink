"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";

const features = [
  {
    id: "reactions",
    title: "Реакции, которые видят все",
    description:
      "Не просто эмодзи в чате — летящие поверх видео реакции. Кто-то смеётся — вы все видите.",
    visual: "reactions",
  },
  {
    id: "chat",
    title: "Чат рядом с кадром",
    description:
      "Обсуждайте, не сворачивая плеер. История сохраняется, можно вернуться к разговору позже.",
    visual: "chat",
  },
  {
    id: "ai",
    title: "AI подбирает, что смотреть",
    description:
      "«Хотим что-то смешное на час» — и Plink предложит варианты из ваших платформ.",
    visual: "ai",
  },
  {
    id: "friends",
    title: "Друзья и групповые чаты",
    description:
      "Личные сообщения, общие комнаты, приглашения. Всё в одном месте, без переключений.",
    visual: "friends",
  },
];

export default function Features() {
  const containerRef = useRef<HTMLDivElement>(null);
  const prefersReducedMotion = useReducedMotion();

  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ["start end", "end start"],
  });

  return (
    <section
      ref={containerRef}
      id="features"
      className="relative py-section-md lg:py-section-lg"
      aria-label="Возможности"
    >
      {/* Subtle bg */}
      <div className="absolute inset-0 bg-surface/30" />

      <div className="container-main relative">
        {/* Header — not centered */}
        <div className="mb-20 grid gap-8 lg:grid-cols-12 lg:items-end">
          <div className="lg:col-span-7">
            <span className="section-label mb-4 block">Что внутри</span>
            <h2 className="text-display text-3xl text-text-primary sm:text-4xl lg:text-5xl">
              Не список функций —<br />
              <span className="text-accent">способы быть ближе</span>
            </h2>
          </div>
          <div className="lg:col-span-4 lg:col-start-9">
            <p className="text-text-secondary">
              Мы убрали всё лишнее, чтобы осталось главное: видео, друзья, общий момент.
            </p>
          </div>
        </div>

        {/* Features grid — asymmetric, overlapping */}
        <div className="grid gap-6 md:grid-cols-2 lg:gap-8">
          {features.map((feature, i) => (
            <motion.div
              key={feature.id}
              initial={{ opacity: 0, y: 40 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-50px" }}
              transition={{
                duration: 0.6,
                delay: prefersReducedMotion ? 0 : i * 0.1,
                ease: [0.32, 0.72, 0, 1],
              }}
              className={`group relative overflow-hidden rounded-3xl border border-surface-2 bg-surface p-8 transition-colors hover:border-accent/30 lg:p-10 ${
                i === 0 ? "md:translate-y-0 lg:row-span-2 lg:h-full" : ""
              } ${i === 1 ? "md:translate-y-8" : ""} ${i === 2 ? "md:-translate-y-4" : ""} ${
                i === 3 ? "md:translate-y-4" : ""
              }`}
            >
              {/* Number */}
              <span className="text-display text-5xl font-bold text-text-muted/20">
                {String(i + 1).padStart(2, "0")}
              </span>

              <h3 className="text-display mt-6 text-xl text-text-primary lg:text-2xl">
                {feature.title}
              </h3>
              <p className="mt-4 text-text-secondary">{feature.description}</p>

              {/* Visual placeholder */}
              <div className="mt-8 flex h-48 items-center justify-center rounded-xl bg-surface-2/50 lg:h-56">
                <FeatureVisual type={feature.visual} />
              </div>

              {/* Hover accent */}
              <div className="pointer-events-none absolute inset-0 rounded-3xl bg-accent/5 opacity-0 transition-opacity duration-500 group-hover:opacity-100" />
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureVisual({ type }: { type: string }) {
  switch (type) {
    case "reactions":
      return (
        <div className="flex items-center gap-3">
          {["😂", "🔥", "😮", "👏"].map((e, i) => (
            <motion.span
              key={i}
              initial={{ scale: 0, y: 20 }}
              whileInView={{ scale: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.1, type: "spring", stiffness: 300 }}
              className="text-3xl"
            >
              {e}
            </motion.span>
          ))}
        </div>
      );
    case "chat":
      return (
        <div className="w-full max-w-[240px] space-y-3">
          <div className="rounded-xl rounded-bl-sm bg-surface-2 px-4 py-2 text-sm">
            а ты видел это?
          </div>
          <div className="ml-auto w-fit rounded-xl rounded-br-sm bg-accent px-4 py-2 text-sm text-bg">
            только что!
          </div>
        </div>
      );
    case "ai":
      return (
        <div className="flex items-center gap-2 rounded-xl bg-surface-2 px-4 py-2">
          <div className="h-2 w-2 animate-pulse rounded-full bg-accent" />
          <span className="text-sm text-text-secondary">Подбираю комедии на 60 минут...</span>
        </div>
      );
    case "friends":
      return (
        <div className="flex -space-x-3">
          {["К", "М", "Д", "Л", "Н"].map((l, i) => (
            <div
              key={i}
              className="flex h-12 w-12 items-center justify-center rounded-full border-2 border-surface bg-surface-2 text-sm font-medium"
            >
              {l}
            </div>
          ))}
        </div>
      );
    default:
      return null;
  }
}
