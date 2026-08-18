#!/usr/bin/env node
/**
 * Offline drift-controller lab.
 *
 * Simulates a viewer player tracking the host reference position and compares
 * the OLD stepped rate controller (1.02 / 1.05 with a 120 ms dead zone) with
 * the M12 P-controller (rate = 1 + clamp(kP * driftMs, ±5%), adaptive window).
 *
 * Scenario (per run, 90 s at 10 Hz):
 *   - starts with a 400 ms post-seek residual offset
 *   - t=30s: player stalls for 500 ms (buffering)
 *   - t=60s: network hiccup instantly adds +250 ms drift
 *   - ±20 ms measurement noise on every controller evaluation
 *
 * Usage: node scripts/controller-sim.mjs [runs]
 */

const TICK = 0.1;
const DURATION = 90;
const RUNS = Number(process.argv[2] || 200);

function simulate(controller) {
  let refPos = 0;
  let playerPos = -0.4; // 400 ms behind after initial seek
  let rate = 1.0;
  let nextEval = 0;
  const samples = [];

  for (let t = 0; t < DURATION; t += TICK) {
    const stalled = t >= 30 && t < 30.5;
    refPos += TICK;
    if (!stalled) playerPos += TICK * rate;
    if (Math.abs(t - 60) < TICK / 2) playerPos -= 0.25;

    const trueDriftMs = (refPos - playerPos) * 1000;
    samples.push({ t, driftMs: trueDriftMs });

    if (t >= nextEval) {
      const measured = trueDriftMs + (Math.random() * 40 - 20);
      const res = controller(measured);
      if (res.seek) {
        playerPos = refPos - 0.05 + Math.random() * 0.1; // seek lands ±50 ms
        rate = 1.0;
      } else {
        rate = res.rate;
      }
      nextEval = t + res.windowSec;
    }
  }
  return samples;
}

// OLD controller (pre-M12): stepped nudges, fixed 2 s window, 120 ms dead zone.
function oldController(driftMs) {
  const abs = Math.abs(driftMs);
  if (abs >= 750) return { seek: true, windowSec: 2 };
  if (abs < 120) return { rate: 1.0, windowSec: 2 };
  const step = abs >= 400 ? 0.05 : 0.02;
  return { rate: driftMs > 0 ? 1 + step : 1 - step, windowSec: 2 };
}

// M12 P-controller: proportional correction, adaptive window, 40 ms dead zone.
function pController(driftMs) {
  const abs = Math.abs(driftMs);
  if (abs >= 750) return { seek: true, windowSec: 2 };
  if (abs < 40) return { rate: 1.0, windowSec: 2 };
  const correction = Math.max(-0.05, Math.min(0.05, 0.0002 * driftMs));
  return { rate: 1 + correction, windowSec: abs >= 250 ? 1 : 2 };
}

function percentile(sorted, p) {
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

function convergenceTime(samples, fromT, thresholdMs = 80, holdSec = 3) {
  let heldSince = null;
  for (const s of samples) {
    if (s.t < fromT) continue;
    if (Math.abs(s.driftMs) <= thresholdMs) {
      if (heldSince === null) heldSince = s.t;
      if (s.t - heldSince >= holdSec) return heldSince - fromT;
    } else {
      heldSince = null;
    }
  }
  return null;
}

function analyze(name, controller) {
  const steady = [];
  const conv0 = [];
  const conv30 = [];
  const conv60 = [];
  for (let r = 0; r < RUNS; r++) {
    const s = simulate(controller);
    for (const x of s) if (x.t >= 20 && x.t < 30) steady.push(Math.abs(x.driftMs));
    const c0 = convergenceTime(s, 0);
    const c30 = convergenceTime(s, 30.5);
    const c60 = convergenceTime(s, 60.1);
    if (c0 !== null) conv0.push(c0);
    if (c30 !== null) conv30.push(c30);
    if (c60 !== null) conv60.push(c60);
  }
  steady.sort((a, b) => a - b);
  const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN);
  console.log(`\n=== ${name} (${RUNS} runs) ===`);
  console.log(
    `steady-state |drift| (t=20..30s): median ${percentile(steady, 50).toFixed(0)} ms, p95 ${percentile(steady, 95).toFixed(0)} ms`,
  );
  console.log(
    `convergence to <80 ms:  cold start ${avg(conv0).toFixed(1)} s | after 500 ms stall ${avg(conv30).toFixed(1)} s | after +250 ms hiccup ${avg(conv60).toFixed(1)} s`,
  );
}

analyze('OLD stepped controller', oldController);
analyze('M12 P-controller', pController);
