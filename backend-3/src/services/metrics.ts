// src/services/metrics.ts — Pack 4: Prometheus metrics
import { register, Counter, Histogram, Gauge } from 'prom-client';

register.clear();

// HTTP metrics
export const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
});

export const httpRequestTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status'],
});

// WebSocket metrics
export const wsConnections = new Gauge({
  name: 'ws_connections_active',
  help: 'Number of active WebSocket connections',
});

export const wsMessages = new Counter({
  name: 'ws_messages_total',
  help: 'Total WebSocket messages',
  labelNames: ['type', 'direction'],
});

// Business metrics
export const roomsActive = new Gauge({
  name: 'rooms_active_total',
  help: 'Number of active rooms',
});

export const usersOnline = new Gauge({
  name: 'users_online_total',
  help: 'Number of online users',
});

export const messagesSent = new Counter({
  name: 'messages_sent_total',
  help: 'Total chat messages sent',
});

export const roomsCreated = new Counter({
  name: 'rooms_created_total',
  help: 'Total rooms created',
});

// Database metrics
export const dbQueryDuration = new Histogram({
  name: 'db_query_duration_seconds',
  help: 'Database query duration',
  labelNames: ['model', 'operation'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1],
});

// Auth metrics
export const authAttempts = new Counter({
  name: 'auth_attempts_total',
  help: 'Authentication attempts',
  labelNames: ['method', 'result'],
});

export { register };
