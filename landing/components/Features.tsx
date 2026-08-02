"use client";

import Image from "next/image";
import { motion, useReducedMotion } from "framer-motion";

const features = [
  {
    id: "room",
    title: "Комната",
    description:
      "Видео, чат и участники — в одном экране. Пауза у одного — пауза у всех. Реакции вылетают поверх кадра.",
    screen: "/screens/room-watching.webp",
  },
  {
    id: "chat",
    title: "Чат",
    description:
      "Текст идёт рядом с видео, не снизу. Сообщения не тонут в ленте — история сохраняется, можно вернуться к моменту позже.",
    screen: "/screens/room-chat.webp",
  },
  {
    id: "friends",
    title: "Друзья",
    description:
      "Видно, кто онлайн прямо сейчас. Приглашение в комнату — одно касание, не серия форм.",
    screen: "/screens/friends.webp",
  },
  {
    id: "themes",
    title: "Оформление",
    description:
      "Живые темы и кастомные акценты — заходишь и сразу видишь, в чьей комнате находишься.",
    screen: "/screens/themes.webp",
  },
];

export default function Features() {
  const prefersReducedMotion = useReducedMotion();

  return (
    <section
      id="features"
      className="relative bg-surface/30 py-24 lg:py-32"
      aria-label="Возможности"
    >
      <div className="container-main relative">
        <div className="mb-20 grid gap-8 lg:grid-cols-12 lg:items-end">
          <div className="lg:col-span-7">
            <span className="section-label mb-4 block">Как это работает</span>
            <h2 className="text-display text-3xl text-text-primary sm:text-4xl lg:text-5xl">
              Комната.
              <br />
              Видео и разговор — в одном кадре.
            </h2>
          </div>
          <div className="lg:col-span-4 lg:col-start-9">
            <p className="text-text-secondary">
              Никаких табов и свернутых окон. Чат живёт под видео, реакции всплывают поверх кадра, участники видны всегда.
            </p>
          </div>
        </div>

        <div className="space-y-24 lg:space-y-32">
          {features.map((feature, i) => {
            const reversed = i % 2 === 1;
            return (
              <div
                key={feature.id}
                className={`grid items-center gap-10 lg:grid-cols-12 lg:gap-16 ${
                  reversed ? "" : ""
                }`}
              >
                {/* Screenshot */}
                <motion.div
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true, margin: "-80px" }}
                  transition={{
                    duration: 0.7,
                    delay: prefersReducedMotion ? 0 : 0.05,
                    ease: [0.32, 0.72, 0, 1],
                  }}
                  className={`relative mx-auto w-full max-w-[280px] lg:col-span-5 ${
                    reversed ? "lg:order-2 lg:col-start-8" : "lg:col-start-1"
                  }`}
                >
                  <div
                    className="relative aspect-[402/874] overflow-hidden rounded-[2rem] border border-surface-2 bg-black"
                    style={{ boxShadow: "0 30px 60px -20px rgba(0,0,0,0.6)" }}
                  >
                    <Image
                      src={feature.screen}
                      alt={`Экран Plink: ${feature.title}`}
                      fill
                      quality={65}
                      loading="lazy"
                      sizes="280px"
                      className="object-cover"
                    />
                  </div>
                </motion.div>

                {/* Text */}
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true, margin: "-80px" }}
                  transition={{
                    duration: 0.6,
                    delay: prefersReducedMotion ? 0 : 0.15,
                    ease: [0.32, 0.72, 0, 1],
                  }}
                  className={`lg:col-span-6 ${
                    reversed ? "lg:order-1 lg:col-start-1" : "lg:col-start-7"
                  }`}
                >
                  <span className="font-mono text-xs text-[#B0B7B3]">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <h3 className="text-display mt-3 text-2xl text-text-primary lg:text-3xl">
                    {feature.title}
                  </h3>
                  <p className="mt-4 max-w-md text-text-secondary">{feature.description}</p>
                </motion.div>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
