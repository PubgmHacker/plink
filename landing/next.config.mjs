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
};

export default nextConfig;
