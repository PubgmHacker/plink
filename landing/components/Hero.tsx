"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { motion, useReducedMotion, AnimatePresence } from "framer-motion";
import { APP_STORE_URL } from "@/lib/constants";

// -- Types ------------------------------------------------------------------
interface DeviceState {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  zIndex: number;
  isPrimary?: boolean;
}

interface Particle {
  id: number;
  x: number;
  emoji: string;
  deviceId: string;
}

// -- Constants ----------------------------------------------------------------
const EMOJIS = ["😂", "🔥", "😮", "👏", "💀", "❤️", "😱", "🤯"];
const CHAT_POOL = [
  { author: "Кирилл", text: "смотри на этот момент" },
  { author: "Маша", text: "я умерла 😂" },
  { author: "Даня", text: "пауза пауза пауза" },
  { author: "Лёша", text: "КАК ОН ЭТО СДЕЛАЛ" },
  { author: "Настя", text: "покажи ещё раз" },
];

// -- Component ----------------------------------------------------------------
export default function Hero() {
  const prefersReducedMotion = useReducedMotion();
  const [mounted, setMounted] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [particles, setParticles] = useState<Particle[]>([]);
  const [chatMsgs, setChatMsgs] = useState<Array<{ id: number; text: string; author: string; time: string }>>([]);
  const [progress, setProgress] = useState(0);
  const [cursorPos, setCursorPos] = useState({ x: 0, y: 0 });
  const [isHoveringPause, setIsHoveringPause] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const particleId = useRef(0);
  const msgId = useRef(0);

  // -- Devices layout ---------------------------------------------------------
  const devices: DeviceState[] = [
    { id: "iphone-main", x: 5, y: 15, width: 280, height: 560, rotation: -4, zIndex: 40, isPrimary: true },
    { id: "iphone-side", x: 62, y: 8, width: 200, height: 400, rotation: 6, zIndex: 30 },
    { id: "iphone-back", x: 28, y: 45, width: 170, height: 340, rotation: -12, zIndex: 20 },
    { id: "ipad", x: 68, y: 48, width: 340, height: 240, rotation: 2, zIndex: 10 },
  ];

  // -- Progress animation -----------------------------------------------------
  useEffect(() => {
    if (!mounted || prefersReducedMotion) return;
    const interval = setInterval(() => {
      if (!isPaused) {
        setProgress((p) => (p >= 100 ? 0 : p + 0.15));
      }
    }, 50);
    return () => clearInterval(interval);
  }, [mounted, isPaused, prefersReducedMotion]);

  // -- Particle system --------------------------------------------------------
  const spawnParticle = useCallback((deviceId: string) => {
    if (prefersReducedMotion) return;
    const id = ++particleId.current;
    const emoji = EMOJIS[Math.floor(Math.random() * EMOJIS.length)];
    setParticles((prev) => [...prev.slice(-12), { id, x: Math.random() * 60 + 20, emoji, deviceId }]);
    setTimeout(() => {
      setParticles((prev) => {
        const others = devices
          .filter((d) => d.id !== deviceId)
          .map((d) => ({ id: id * 1000 + Math.random(), x: Math.random() * 60 + 20, emoji, deviceId: d.id }));
        return [...prev, ...others];
      });
    }, 150);
    setTimeout(() => {
      setParticles((prev) => prev.filter((p) => p.id !== id && !String(p.id).startsWith(String(id * 1000))));
    }, 3000);
  }, [prefersReducedMotion]);

  // -- Auto spawn particles ---------------------------------------------------
  useEffect(() => {
    if (!mounted || prefersReducedMotion) return;
    const interval = setInterval(() => {
      if (Math.random() > 0.4) {
        const device = devices[Math.floor(Math.random() * devices.length)];
        spawnParticle(device.id);
      }
    }, 800);
    return () => clearInterval(interval);
  }, [mounted, spawnParticle, prefersReducedMotion]);

  // -- Chat messages ----------------------------------------------------------
  useEffect(() => {
    if (!mounted || prefersReducedMotion) return;
    const interval = setInterval(() => {
      if (Math.random() > 0.6) {
        const msg = CHAT_POOL[Math.floor(Math.random() * CHAT_POOL.length)];
        const now = new Date();
        const time = `${now.getHours().toString().padStart(2, "0")}:${now.getMinutes().toString().padStart(2, "0")}`;
        setChatMsgs((prev) => [...prev.slice(-4), { ...msg, id: ++msgId.current, time }]);
      }
    }, 2500);
    return () => clearInterval(interval);
  }, [mounted, prefersReducedMotion]);

  // -- Cursor tracking --------------------------------------------------------
  useEffect(() => {
    if (prefersReducedMotion) return;
    const handleMove = (e: MouseEvent) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      setCursorPos({
        x: (e.clientX - rect.left) / rect.width - 0.5,
        y: (e.clientY - rect.top) / rect.height - 0.5,
      });
    };
    window.addEventListener("mousemove", handleMove, { passive: true });
    return () => window.removeEventListener("mousemove", handleMove);
  }, [prefersReducedMotion]);

  // -- Mount ------------------------------------------------------------------
  useEffect(() => setMounted(true), []);

  // -- Device render ----------------------------------------------------------
  const renderDevice = (device: DeviceState) => {
    const isPrimary = device.isPrimary;
    const parallaxX = cursorPos.x * (isPrimary ? -15 : -8);
    const parallaxY = cursorPos.y * (isPrimary ? -10 : -5);

    return (
      <motion.div
        key={device.id}
        className="absolute"
        style={{
          left: `${device.x}%`,
          top: `${device.y}%`,
          zIndex: device.zIndex,
          width: device.width,
          height: device.height,
        }}
        initial={{
          opacity: 0,
          y: 60,
          rotate: device.rotation,
          x: parallaxX,
        }}
        animate={{
          opacity: 1,
          y: parallaxY,
          x: parallaxX,
          rotate: device.rotation,
        }}
        transition={{
          duration: 0.8,
          delay: devices.indexOf(device) * 0.12,
          ease: [0.32, 0.72, 0, 1],
        }}
      >
        {/* Device frame */}
        <div
          className="relative h-full w-full overflow-hidden rounded-[2rem] border border-surface-2 bg-surface"
          style={{
            boxShadow: `0 25px 60px -12px rgba(0,0,0,0.6), 0 0 ${isPrimary ? "80px" : "40px"} rgba(200,255,61,${isPrimary ? 0.08 : 0.03})`,
          }}
        >
          {/* Notch */}
          {isPrimary && (
            <div className="absolute left-1/2 top-3 z-30 h-6 w-24 -translate-x-1/2 rounded-full bg-black" />
          )}

          {/* Screen */}
          <div className="absolute inset-0 bg-surface-2">
            {/* Video content */}
            <div className="absolute inset-x-0 top-0 h-[70%] overflow-hidden">
              <div className="relative h-full w-full bg-gradient-to-br from-[#1a1a2e] to-[#16213e]">
                {/* Sync indicator */}
                <div className="absolute right-3 top-3 z-20 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 backdrop-blur-sm">
                  <div className={`h-1.5 w-1.5 rounded-full ${isPaused ? "bg-sync" : "bg-accent"} ${!prefersReducedMotion && !isPaused ? "animate-pulse" : ""}`} />
                  <span className="text-[10px] font-medium text-white/90">
                    {isPaused ? "Пауза" : "Синхронно"}
                  </span>
                </div>

                {/* Play/Pause button */}
                {isPrimary && (
                  <button
                    onClick={() => setIsPaused(!isPaused)}
                    onMouseEnter={() => setIsHoveringPause(true)}
                    onMouseLeave={() => setIsHoveringPause(false)}
                    className="absolute left-1/2 top-[35%] z-20 flex h-16 w-16 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white/10 backdrop-blur-md transition-all duration-300 hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-accent"
                    aria-label={isPaused ? "Воспроизвести" : "Пауза"}
                  >
                    {isPaused ? (
                      <svg width="24" height="24" viewBox="0 0 24 24" fill="white" aria-hidden="true">
                        <path d="M8 5v14l11-7z" />
                      </svg>
                    ) : (
                      <svg width="24" height="24" viewBox="0 0 24 24" fill="white" aria-hidden="true">
                        <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                      </svg>
                    )}
                  </button>
                )}

                {/* Progress bar */}
                <div className="absolute bottom-0 left-0 right-0 z-20 p-3">
                  <div className="h-1 w-full overflow-hidden rounded-full bg-white/20">
                    <div
                      className="h-full rounded-full bg-accent transition-none"
                      style={{ width: `${progress}%` }}
                    />
                  </div>
                  <div className="mt-1.5 flex justify-between text-[10px] text-white/60">
                    <span>{formatTime(progress * 0.6)}</span>
                    <span>1:00:00</span>
                  </div>
                </div>

                {/* Particles */}
                <AnimatePresence>
                  {particles
                    .filter((p) => p.deviceId === device.id)
                    .map((p) => (
                      <motion.div
                        key={p.id}
                        initial={{ opacity: 0, y: 20, scale: 0.5 }}
                        animate={{ opacity: 1, y: -40, scale: 1.2 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 1.5, ease: "easeOut" }}
                        className="absolute z-10 text-2xl"
                        style={{ left: `${p.x}%`, bottom: "10%" }}
                      >
                        {p.emoji}
                      </motion.div>
                    ))}
                </AnimatePresence>
              </div>
            </div>

            {/* Chat */}
            <div className="absolute bottom-0 left-0 right-0 h-[30%] border-t border-white/5 bg-surface/80 backdrop-blur-sm">
              <div className="flex h-full flex-col justify-end p-3">
                <AnimatePresence mode="popLayout">
                  {chatMsgs.slice(-3).map((msg) => (
                    <motion.div
                      key={msg.id}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: 0.3 }}
                      className="mb-1.5 last:mb-0"
                    >
                      <div className="text-[10px] text-text-secondary">
                        <span className="font-medium text-accent">{msg.author}</span>
                        <span className="mx-1">·</span>
                        <span>{msg.time}</span>
                      </div>
                      <div className="text-[11px] text-white/90">{msg.text}</div>
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>
            </div>
          </div>
        </div>

        {/* Glow */}
        {isPrimary && (
          <div
            className="absolute -inset-8 -z-10 rounded-[3rem] opacity-20 blur-3xl transition-opacity duration-500"
            style={{
              background: `radial-gradient(ellipse at center, ${isHoveringPause ? "rgba(255,92,57,0.4)" : "rgba(200,255,61,0.3)"} 0%, transparent 70%)`,
            }}
          />
        )}
      </motion.div>
    );
  };

  return (
    <section
      ref={containerRef}
      className="relative min-h-screen overflow-hidden pt-20"
      aria-label="Plink — совместный просмотр видео"
    >
      {/* Background */}
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <div className="absolute left-1/4 top-0 h-[600px] w-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent/[0.03] blur-[120px]" />
        <div className="absolute bottom-0 right-0 h-[400px] w-[400px] translate-x-1/3 translate-y-1/3 rounded-full bg-sync/[0.02] blur-[100px]" />
      </div>

      <div className="container-main relative z-10">
        <div className="grid min-h-[calc(100vh-5rem)] grid-cols-1 items-center gap-12 py-12 lg:grid-cols-12 lg:gap-8">
          {/* Text */}
          <div className="lg:col-span-5 lg:col-start-1">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, ease: [0.32, 0.72, 0, 1] }}
            >
              <div className="mb-6 flex items-center gap-3">
                <span className="section-label">iOS</span>
                <span className="h-px w-8 bg-text-muted" aria-hidden="true" />
                <span className="section-label">Бесплатно</span>
              </div>

              <h1 className="text-display text-5xl leading-[1.05] text-text-primary sm:text-6xl lg:text-7xl">
                Один кадр.
                <br />
                <span className="text-gradient">Одна пауза.</span>
                <br />
                Одна комната.
              </h1>

              <p className="mt-8 max-w-md text-lg leading-relaxed text-text-secondary">
                Смотри YouTube, VK Видео и Rutube синхронно с друзьями.
                Создай комнату, отправь код — и смотрите вместе,
                где бы вы ни были.
              </p>

              <div className="mt-8 inline-flex items-center gap-4 rounded-xl border border-surface-2 bg-surface px-5 py-3">
                <span className="text-xs text-text-muted">Код комнаты</span>
                <code className="text-display text-lg font-semibold tracking-[0.3em] text-accent">
                  K7XQ2M
                </code>
                <button
                  className="rounded-lg bg-surface-2 px-3 py-1.5 text-xs font-medium text-text-secondary transition-colors hover:bg-accent hover:text-bg focus:outline-none focus:ring-2 focus:ring-accent"
                  aria-label="Скопировать код комнаты"
                >
                  Копировать
                </button>
              </div>

              <div className="mt-10 flex flex-wrap items-center gap-4">
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group inline-flex items-center gap-3 rounded-xl bg-accent px-8 py-4 text-base font-semibold text-bg transition-all duration-300 hover:bg-accent-dim focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 focus:ring-offset-bg"
                >
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-.81 3.19-.51.87-1.63 1.82-2.68 1.78-.13-1.19.33-2.42.55-3.47z" />
                  </svg>
                  Скачать в App Store
                </a>
                <a
                  href="#how-it-works"
                  className="inline-flex items-center gap-2 rounded-xl border border-surface-2 px-6 py-4 text-base font-medium text-text-secondary transition-all duration-300 hover:border-text-muted hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
                >
                  Как это работает
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                    <path d="M19 14l-7 7m0 0l-7-7m7 7V3" />
                  </svg>
                </a>
              </div>
            </motion.div>
          </div>

          {/* Devices */}
          <div className="relative h-[500px] sm:h-[600px] lg:col-span-7 lg:h-[700px]">
            {devices.map(renderDevice)}
          </div>
        </div>
      </div>

      {/* Scroll hint */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.5, duration: 0.6 }}
        className="absolute bottom-8 left-1/2 z-10 -translate-x-1/2"
        aria-hidden="true"
      >
        <div className="flex flex-col items-center gap-2 text-text-muted">
          <span className="text-xs">Листай</span>
          <div className="h-8 w-px bg-text-muted" />
        </div>
      </motion.div>
    </section>
  );
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}
