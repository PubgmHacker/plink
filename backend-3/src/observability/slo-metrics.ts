// src/observability/slo-metrics.ts — Stage 13 telemetry (runbook §14)
//
// All SLO metrics from runbook §14, no PII or tokens:
//   room_join_duration_ms
//   player_startup_ms
//   player_rebuffer_count
//   player_rebuffer_ratio
//   sync_command_delivery_ms
//   sync_drift_ms
//   sync_hard_correction_count
//   ws_reconnect_count
//   rtc_packet_loss
//   rtc_jitter_ms
//   provider_playback_error{provider,code}

import { Counter, Histogram, Gauge } from 'prom-client';
import { register } from '../services/metrics.js';

export const roomJoinDuration = new Histogram({
  name: 'plink_room_join_duration_ms',
  help: 'Time from WS connect to session.ready + snapshot received',
  buckets: [100, 250, 500, 1000, 2000, 3000, 5000, 10000],
  registers: [register],
});

export const playerStartup = new Histogram({
  name: 'plink_player_startup_ms',
  help: 'Time from prepare() call to first frame rendered',
  buckets: [100, 250, 500, 1000, 2000, 3000, 5000],
  registers: [register],
});

export const playerRebufferCount = new Counter({
  name: 'plink_player_rebuffer_count_total',
  help: 'Number of rebuffers during playback',
  labelNames: ['room_id'],
  registers: [register],
});

export const playerRebufferRatio = new Gauge({
  name: 'plink_player_rebuffer_ratio',
  help: 'Ratio of rebuffer time to total playback time',
  labelNames: ['room_id'],
  registers: [register],
});

export const syncCommandDelivery = new Histogram({
  name: 'plink_sync_command_delivery_ms',
  help: 'Time from sync.command publish to client receipt',
  buckets: [10, 25, 50, 100, 180, 250, 500, 1000],
  registers: [register],
});

export const syncDrift = new Histogram({
  name: 'plink_sync_drift_ms',
  help: 'Playback drift in milliseconds',
  buckets: [10, 40, 80, 150, 250, 500, 750, 1000, 2000],
  registers: [register],
});

export const syncHardCorrections = new Counter({
  name: 'plink_sync_hard_correction_count_total',
  help: 'Number of precise seeks triggered by drift >= 750ms',
  labelNames: ['room_id'],
  registers: [register],
});

export const wsReconnectCount = new Counter({
  name: 'plink_ws_reconnect_count_total',
  help: 'Number of WebSocket reconnections',
  labelNames: ['room_id', 'reason'],
  registers: [register],
});

export const rtcPacketLoss = new Gauge({
  name: 'plink_rtc_packet_loss',
  help: 'RTC packet loss percentage',
  labelNames: ['room_id'],
  registers: [register],
});

export const rtcJitter = new Gauge({
  name: 'plink_rtc_jitter_ms',
  help: 'RTC jitter in milliseconds',
  labelNames: ['room_id'],
  registers: [register],
});

export const providerPlaybackError = new Counter({
  name: 'plink_provider_playback_error_total',
  help: 'Playback errors by provider and error code',
  labelNames: ['provider', 'code'],
  registers: [register],
});

export const presenceLeaseCount = new Gauge({
  name: 'plink_presence_lease_count',
  help: 'Number of active presence leases',
  labelNames: ['room_id'],
  registers: [register],
});
