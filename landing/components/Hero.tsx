"use client";

import { useEffect, useRef, useState } from "react";
import {
  motion,
  AnimatePresence,
  useMotionValue,
  useSpring,
  useTransform,
  MotionValue,
  useReducedMotion,
} from "framer-motion";
import { APP_STORE_URL } from "@/lib/constants";

// -- Static data ---------------------------------------------------------------
const DEVICES = [
  {
    id: "iphone-main",
    type: "iphone" as const,
    x: 8, y: 12, width: 300, height: 610,
    rotation: -3,
    zIndex: 40,
    isPrimary: true,
  },
  {
    id: "iphone-side",
    type: "iphone" as const,
    x: 62, y: 5, width: 240, height: 490,
    rotation: 5,
    zIndex: 30,
  },
  {
    id: "iphone-back",
    type: "iphone" as const,
    x: 32, y: 45, width: 200, height: 410,
    rotation: -10,
    zIndex: 20,
  },
  {
    id: "ipad",
    type: "ipad" as const,
    x: 68, y: 48, width: 380, height: 270,
    rotation: 2,
    zIndex: 10,
  },
] as const;

const DEVICE_IDS = DEVICES.map((d) => d.id);

const EMOJIS = ["😂", "🔥", "😮", "👏", "💀", "❤️", "😱", "🤯"];
const CHAT_POOL = [
  { author: "Кирилл", text: "смотри на этот момент" },
  { author: "Маша", text: "я умерла 😂" },
  { author: "Даня", text: "пауза пауза пауза" },
  { author: "Лёша", text: "КАК ОН ЭТО СДЕЛАЛ" },
  { author: "Настя", text: "покажи ещё раз" },
];

const PROGRESS_MAX = 100;
const PROGRESS_STEP = 0.12;
const SYNC_DELAY_MS = 150;
const PARTICLE_LIFE_MS = 2800;

interface Particle {
  id: number;
  x: number;
  emoji: string;
  deviceId: string;
}

interface ChatMsg {
  id: number;
  text: string;
  author: string;
  time: string;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

// -- Device Frame ----------------------------------------------------------------
interface DeviceFrameProps {
  device: (typeof DEVICES)[number];
  index: number;
  smoothX: MotionValue<number>;
  smoothY: MotionValue<number>;
  isPaused: boolean;
  setIsPaused: (v: boolean) => void;
  isHoveringPause: boolean;
  setIsHoveringPause: (v: boolean) => void;
  particles: Particle[];
  chatMsgs: ChatMsg[];
  progress: number;
  prefersReducedMotion: boolean;
}

function DeviceFrame({
  device,
  index,
  smoothX,
  smoothY,
  isPaused,
  setIsPaused,
  isHoveringPause,
  setIsHoveringPause,
  particles,
  chatMsgs,
  progress,
  prefersReducedMotion,
}: DeviceFrameProps) {
  const isPrimary = "isPrimary" in device && (device as { isPrimary?: boolean }).isPrimary;
  const multX = isPrimary ? -12 : device.type === "ipad" ? -6 : -8;
  const multY = isPrimary ? -8 : device.type === "ipad" ? -4 : -5;

  // Spring-animated parallax without re-renders
  const x = useTransform(smoothX, (v) => v * multX);
  const y = useTransform(smoothY, (v) => v * multY);
  const springX = useSpring(x, { stiffness: 150, damping: 25 });
  const springY = useSpring(y, { stiffness: 150, damping: 25 });

  const deviceParticles = particles.filter((p) => p.deviceId === device.id);
  const isIphone = device.type === "iphone";

  return (
    <motion.div
      className="absolute"
      style={{
        left: `${device.x}%`,
        top: `${device.y}%`,
        zIndex: device.zIndex,
        width: device.width,
        height: device.height,
        x: springX,
        y: springY,
        rotate: device.rotation,
      }}
      initial={{ opacity: 0, scale: 0.92 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{
        duration: 0.9,
        delay: index * 0.15,
        ease: [0.32, 0.72, 0, 1],
      }}
    >
      {/* Physical device frame */}
      <div
        className={`relative h-full w-full overflow-hidden ${
          isIphone ? "rounded-[2.5rem]" : "rounded-3xl"
        } bg-black`}
        style={{
          border: "1px solid rgba(255,255,255,0.12)",
          boxShadow: `
            0 25px 50px -12px rgba(0,0,0,0.7),
            0 0 ${isPrimary ? "100px" : "50px"} rgba(255,107,74,${isPrimary ? 0.1 : 0.04}),
            inset 0 1px 0 rgba(255,255,255,0.08)
          `,
        }}
      >
        {/* Notch */}
        {isIphone && (
          <div className="absolute left-1/2 top-2 z-30 h-6 w-28 -translate-x-1/2 rounded-full bg-black border border-neutral-800" />
        )}
        {/* Home indicator for iPad */}
        {!isIphone && (
          <div className="absolute bottom-2 left-1/2 z-30 h-1 w-32 -translate-x-1/2 rounded-full bg-neutral-600" />
        )}

        {/* Screen content */}
        <div className="absolute inset-0 overflow-hidden bg-neutral-950">
          {/* Video area — animated gradient as living content */}
          <div className="absolute inset-x-0 top-0 h-[68%] overflow-hidden">
            {/* Animated gradient background simulating video */}
            <div
              className="absolute inset-0 transition-opacity duration-700"
              style={{
                background: isPaused
                  ? "linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)"
                  : undefined,
                opacity: isPaused ? 0.6 : 1,
              }}
            >
              {!isPaused && (
                <motion.div
                  className="absolute inset-0"
                  animate={{
                    background: [
                      "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
                      "linear-gradient(225deg, #f093fb 0%, #f5576c 100%)",
                      "linear-gradient(315deg, #4facfe 0%, #00f2fe 100%)",
                      "linear-gradient(135deg, #667eea 0%, #764ba2 100%)",
                    ],
                  }}
                  transition={{
                    duration: 20,
                    repeat: Infinity,
                    ease: "linear",
                  }}
                />
              )}
              {/* Video overlay texture */}
              <div className="absolute inset-0 bg-gradient-to-t from-black/40 via-transparent to-transparent" />
            </div>

            {/* Sync badge */}
            <div className="absolute right-3 top-3 z-20 flex items-center gap-1.5 rounded-full bg-black/70 px-2.5 py-1 backdrop-blur-md">
              <div
                className={`h-1.5 w-1.5 rounded-full ${
                  isPaused ? "bg-sync" : "bg-accent"
                } ${!prefersReducedMotion && !isPaused ? "animate-pulse" : ""}`}
              />
              <span className="text-[10px] font-medium text-white/90">
                {isPaused ? "Пауза" : "В эфире"}
              </span>
            </div>

            {/* Play/Pause — only primary */}
            {isPrimary && (
              <button
                onClick={() => setIsPaused(!isPaused)}
                onMouseEnter={() => setIsHoveringPause(true)}
                onMouseLeave={() => setIsHoveringPause(false)}
                className="absolute left-1/2 top-[40%] z-20 flex h-14 w-14 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-black/50 backdrop-blur-md transition-all duration-300 hover:bg-black/70 focus:outline-none focus:ring-2 focus:ring-accent"
                aria-label={isPaused ? "Воспроизвести" : "Пауза"}
              >
                {isPaused ? (
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="white" aria-hidden="true">
                    <path d="M8 5v14l11-7z" />
                  </svg>
                ) : (
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="white" aria-hidden="true">
                    <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                  </svg>
                )}
              </button>
            )}

            {/* Progress bar */}
            <div className="absolute bottom-0 left-0 right-0 z-20 p-3">
              <div className="h-[3px] w-full overflow-hidden rounded-full bg-white/15">
                <div
                  className="h-full rounded-full bg-accent transition-none"
                  style={{ width: `${progress}%` }}
                />
              </div>
              <div className="mt-1.5 flex justify-between text-[10px] text-white/50 font-mono">
                <span>{formatTime(progress * 0.42)}</span>
                <span>-{formatTime(42 - progress * 0.42)}</span>
              </div>
            </div>

            {/* Particles */}
            <AnimatePresence>
              {deviceParticles.map((p) => (
                <motion.span
                  key={p.id}
                  initial={{ opacity: 0, y: 30, scale: 0.4 }}
                  animate={{ opacity: 1, y: -50, scale: 1.1 }}
                  exit={{ opacity: 0, y: -80 }}
                  transition={{
                    duration: prefersReducedMotion ? 0.01 : 1.8,
                    ease: [0.16, 1, 0.3, 1],
                  }}
                  className="absolute z-10 text-xl"
                  style={{ left: `${p.x}%`, bottom: "15%" }}
                >
                  {p.emoji}
                </motion.span>
              ))}
            </AnimatePresence>
          </div>

          {/* Chat */}
          <div className="absolute bottom-0 left-0 right-0 h-[32%] border-t border-neutral-800 bg-black/90 backdrop-blur-sm">
            <div className="flex h-full flex-col justify-end p-3">
              <AnimatePresence mode="popLayout">
                {chatMsgs.slice(-3).map((msg) => (
                  <motion.div
                    key={msg.id}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -10 }}
                    transition={{ duration: 0.3 }}
                    className="mb-1.5 last:mb-0"
                  >
                    <div className="text-[10px] text-neutral-500">
                      <span className="font-medium text-accent">{msg.author}</span>
                      <span className="mx-1">·</span>
                      <span>{msg.time}</span>
                    </div>
                    <div className="text-[11px] text-neutral-300">{msg.text}</div>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          </div>
        </div>
      </div>

      {/* Ambient glow for primary */}
      {isPrimary && (
        <div
          className="absolute -inset-10 -z-10 rounded-[3rem] opacity-20 blur-3xl transition-opacity duration-500"
          style={{
            background: `radial-gradient(ellipse at center, ${
              isHoveringPause ? "rgba(255,107,74,0.25)" : "rgba(255,107,74,0.08)"
            } 0%, transparent 70%)`,
          }}
        />
      )}
    </motion.div>
  );
}

// -- Main Hero ---------------------------------------------------------------------
export default function Hero() {
  const prefersReducedMotion = useReducedMotion();
  const [isPaused, setIsPaused] = useState(false);
  const [particles, setParticles] = useState<Particle[]>([]);
  const [chatMsgs, setChatMsgs] = useState<ChatMsg[]>([]);
  const [progress, setProgress] = useState(0);
  const [isHoveringPause, setIsHoveringPause] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const particleId = useRef(0);
  const msgId = useRef(0);
  const progressRef = useRef(0);

  const cursorX = useMotionValue(0);
  const cursorY = useMotionValue(0);
  const smoothX = useSpring(cursorX, { stiffness: 120, damping: 20 });
  const smoothY = useSpring(cursorY, { stiffness: 120, damping: 20 });

  // -- Progress ----------------------------------------------------------------
  useEffect(() => {
    if (prefersReducedMotion) return;
    let frame: number;
    const tick = () => {
      if (!isPaused) {
        progressRef.current =
          progressRef.current >= PROGRESS_MAX ? 0 : progressRef.current + PROGRESS_STEP;
        setProgress(progressRef.current);
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [isPaused, prefersReducedMotion]);

  // -- Particles ---------------------------------------------------------------
  const spawnParticle = (deviceId: string) => {
    if (prefersReducedMotion) return;
    const id = ++particleId.current;
    const emoji = EMOJIS[Math.floor(Math.random() * EMOJIS.length)];
    setParticles((prev) => [...prev.slice(-12), { id, x: Math.random() * 60 + 20, emoji, deviceId }]);
    setTimeout(() => {
      setParticles((prev) => {
        const others = DEVICE_IDS.filter((d) => d !== deviceId).map((d) => ({
          id: id * 1000 + Math.random(),
          x: Math.random() * 60 + 20,
          emoji,
          deviceId: d,
        }));
        return [...prev, ...others];
      });
    }, SYNC_DELAY_MS);
    setTimeout(() => {
      setParticles((prev) =>
        prev.filter((p) => p.id !== id && !String(p.id).startsWith(String(id * 1000)))
      );
    }, PARTICLE_LIFE_MS);
  };

  useEffect(() => {
    if (prefersReducedMotion) return;
    const interval = setInterval(() => {
      if (Math.random() > 0.4) {
        spawnParticle(DEVICES[Math.floor(Math.random() * DEVICES.length)].id);
      }
    }, 900);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prefersReducedMotion]);

  // -- Chat --------------------------------------------------------------------
  useEffect(() => {
    if (prefersReducedMotion) return;
    const interval = setInterval(() => {
      if (Math.random() > 0.5) {
        const msg = CHAT_POOL[Math.floor(Math.random() * CHAT_POOL.length)];
        const now = new Date();
        const time = `${now.getHours().toString().padStart(2, "0")}:${now
          .getMinutes()
          .toString()
          .padStart(2, "0")}`;
        setChatMsgs((prev) => [...prev.slice(-4), { ...msg, id: ++msgId.current, time }]);
      }
    }, 2200);
    return () => clearInterval(interval);
  }, [prefersReducedMotion]);

  // -- Cursor parallax --------------------------------------------------------
  useEffect(() => {
    if (prefersReducedMotion) return;
    const handleMove = (e: MouseEvent) => {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      cursorX.set((e.clientX - rect.left) / rect.width - 0.5);
      cursorY.set((e.clientY - rect.top) / rect.height - 0.5);
    };
    window.addEventListener("mousemove", handleMove, { passive: true });
    return () => window.removeEventListener("mousemove", handleMove);
  }, [prefersReducedMotion, cursorX, cursorY]);

  return (
    <section
      ref={containerRef}
      className="relative min-h-screen overflow-hidden bg-bg"
      aria-label="Plink — совместный просмотр видео"
    >
      {/* Subtle texture — no floating blobs */}
      <div className="pointer-events-none absolute inset-0 opacity-[0.03]">
        <div className="h-full w-full" style={{
          backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(255,255,255,0.03) 2px, rgba(255,255,255,0.03) 4px)`,
        }} />
      </div>

      <div className="container-main relative z-10 pt-24 lg:pt-28">
        <div className="grid min-h-[calc(100vh-7rem)] grid-cols-1 items-center gap-16 py-12 lg:grid-cols-12 lg:gap-8">
          {/* Text */}
          <div className="lg:col-span-5 lg:col-start-1">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, ease: [0.32, 0.72, 0, 1] }}
            >
              <div className="mb-6 flex items-center gap-3">
                <span className="text-[10px] font-medium uppercase tracking-[0.25em] text-text-muted">
                  iOS 16+
                </span>
                <span className="h-px w-6 bg-text-muted" aria-hidden="true" />
                <span className="text-[10px] font-medium uppercase tracking-[0.25em] text-text-muted">
                  Бесплатно
                </span>
              </div>

              <h1 className="text-display text-4xl leading-[1.08] text-text-primary sm:text-5xl lg:text-6xl">
                Один кадр.
                <br />
                <span className="text-accent">Одна пауза.</span>
                <br />
                Одна комната.
              </h1>

              <p className="mt-8 max-w-md text-[15px] leading-relaxed text-text-secondary">
                Смотри YouTube, VK Видео и Rutube синхронно с друзьями.
                Создай комнату, отправь код — и смотрите вместе,
                где бы вы ни были.
              </p>

              <div className="mt-8 inline-flex items-center gap-4 rounded-lg border border-neutral-800 bg-surface px-4 py-3">
                <span className="text-[10px] text-text-muted uppercase tracking-wider">Код комнаты</span>
                <code className="text-display text-base font-semibold tracking-[0.25em] text-accent">
                  K7XQ2M
                </code>
                <button
                  className="rounded bg-neutral-800 px-2.5 py-1 text-[10px] font-medium text-neutral-400 transition-colors hover:bg-accent hover:text-bg focus:outline-none focus:ring-2 focus:ring-accent"
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
                  className="inline-flex items-center gap-2.5 rounded-lg bg-accent px-7 py-3.5 text-[15px] font-semibold text-bg transition-all duration-300 hover:bg-accent-dim focus:outline-none focus:ring-2 focus:ring-accent focus:ring-offset-2 focus:ring-offset-bg"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-.81 3.19-.51.87-1.63 1.82-2.68 1.78-.13-1.19.33-2.42.55-3.47z" />
                  </svg>
                  Скачать в App Store
                </a>
                <a
                  href="#how-it-works"
                  className="inline-flex items-center gap-2 rounded-lg border border-neutral-700 px-5 py-3.5 text-[15px] font-medium text-text-secondary transition-all duration-300 hover:border-neutral-500 hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
                >
                  Как это работает
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                    <path d="M19 14l-7 7m0 0l-7-7m7 7V3" />
                  </svg>
                </a>
              </div>
            </motion.div>
          </div>

          {/* Devices */}
          <div className="relative h-[480px] sm:h-[620px] lg:col-span-7 lg:h-[720px]">
            {DEVICES.map((device, i) => (
              <DeviceFrame
                key={device.id}
                device={device}
                index={i}
                smoothX={smoothX}
                smoothY={smoothY}
                isPaused={isPaused}
                setIsPaused={setIsPaused}
                isHoveringPause={isHoveringPause}
                setIsHoveringPause={setIsHoveringPause}
                particles={particles}
                chatMsgs={chatMsgs}
                progress={progress}
                prefersReducedMotion={!!prefersReducedMotion}
              />
            ))}
          </div>
        </div>
      </div>

      {/* Scroll indicator */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.8, duration: 0.8 }}
        className="absolute bottom-8 left-1/2 z-10 -translate-x-1/2"
        aria-hidden="true"
      >
        <div className="flex flex-col items-center gap-2 text-text-muted">
          <span className="text-[10px] uppercase tracking-wider">Листай</span>
          <div className="h-6 w-px bg-gradient-to-b from-text-muted to-transparent" />
        </div>
      </motion.div>
    </section>
  );
}
