"use client";

import { useEffect, useRef } from "react";

/**
 * Aurora Waves — procedural multi-layer gradient mesh.
 * Same as seen on modern ramp/landing pages — smooth curves lerping through
 * slate/mint/emerald tones, wrapped in a subtle noise texture.
 * Renders onto canvas; zero dependencies.
 */
export default function AuroraWaves() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef<number>(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d", { alpha: false });
    if (!ctx) return;

    let t = 0;
    const DPR = Math.min(window.devicePixelRatio ?? 1, 2);

    const resize = () => {
      canvas.width = canvas.offsetWidth * DPR;
      canvas.height = canvas.offsetHeight * DPR;
      ctx.scale(DPR, DPR);
    };
    resize();
    window.addEventListener("resize", resize);

    const layers = [
      { ampY: 0.18, offY: 0.55, hue: 158, freq: 1.0, alpha: 0.10 },  // green-blue
      { ampY: 0.25, offY: 0.72, hue: 178, freq: 0.7, alpha: 0.08 },  // mint
      { ampY: 0.12, offY: 0.45, hue: 145, freq: 1.3, alpha: 0.11 },  // teal
    ];

    const render = () => {
      const w = canvas.offsetWidth;
      const h = canvas.offsetHeight;
      if (!w || !h) return;

      // Dark base
      const base = ctx.createLinearGradient(0, 0, 0, h);
      base.addColorStop(0, "#0c0f0e");
      base.addColorStop(1, "#151d1a");
      ctx.fillStyle = base;
      ctx.fillRect(0, 0, w, h);

      // Wave layers — each a smooth path
      layers.forEach(({ ampY, offY, hue, freq, alpha }, i) => {
        ctx.beginPath();
        ctx.moveTo(0, h);

        const yBase = h * offY;
        const steps = Math.max(120, Math.floor(w / 4));

        for (let x = 0; x <= steps; x++) {
          const pct = x / steps;
          const freqT = t * 0.35 * freq + i * 0.8;
          const y =
            yBase +
            Math.sin(pct * Math.PI * 1.5 + freqT) * (h * ampY) +
            Math.cos(pct * Math.PI * 3.2 + freqT * 0.67) * (h * ampY * 0.25);
          ctx.lineTo((x / steps) * w, y);
        }
        ctx.lineTo(w, h);
        ctx.closePath();

        const grad = ctx.createLinearGradient(0, yBase - h * ampY * 0.8, 0, h);
        grad.addColorStop(0, `hsla(${hue}, 45%, 52%, ${alpha})`);
        grad.addColorStop(1, `hsla(${hue}, 38%, 28%, 0)`);
        ctx.fillStyle = grad;
        ctx.fill();
      });

      // Grain overlay
      ctx.fillStyle = "rgba(0, 0, 0, 0.04)";
      for (let i = 0; i < w * h * 0.012; i++) {
        const rx = Math.random() * w;
        const ry = Math.random() * h;
        ctx.fillRect(rx, ry, 1, 1);
      }

      t += 0.0045;
      rafRef.current = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(rafRef.current);
      window.removeEventListener("resize", resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", display: "block" }}
    />
  );
}
