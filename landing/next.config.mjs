// Заголовки безопасности для всех маршрутов. CSP сознательно не добавлен:
// inline-стили framer-motion и шрифты next/font требуют отдельного аудита
// перед тем, как политика перестанет ломать страницу.
const securityHeaders = [
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=63072000; includeSubDomains; preload',
  },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];

/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    // Отдаём меньше промежуточных размеров и держим качество умеренным —
    // hero-скриншоты уже сжаты в источнике, повторное ужимание Next.js
    // экономит вес на мобильном без потери читаемости UI на превью.
    deviceSizes: [360, 480, 640, 828, 1080, 1200, 1920],
    imageSizes: [16, 32, 48, 64, 96, 128, 256, 320],
    formats: ['image/webp'],
    minimumCacheTTL: 31536000,
  },
  async headers() {
    return [{ source: '/:path*', headers: securityHeaders }];
  },
};

export default nextConfig;
