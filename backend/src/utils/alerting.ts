// src/utils/alerting.ts — Slack/Telegram alerting
import { config } from '../config/index.js';

export async function alertSlack(
  message: string,
  severity: 'info' | 'warning' | 'critical' = 'warning'
) {
  if (!config.SLACK_WEBHOOK_URL) return;
  
  const emoji = severity === 'critical' ? ':rotating_light:' :
                severity === 'warning' ? ':warning:' : ':information_source:';
  
  try {
    await fetch(config.SLACK_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: `${emoji} [${severity.toUpperCase()}] [${config.NODE_ENV}] ${message}`,
      }),
    });
  } catch (e: any) {
    console.error('[Alerting] Slack failed:', e.message);
  }
}

export async function alertCritical(message: string, error?: Error) {
  const full = error ? `${message}\n\`\`\`${error.stack || error.message}\`\`\`` : message;
  await alertSlack(full, 'critical');
}

export async function alertWarning(message: string) {
  await alertSlack(message, 'warning');
}
