import type { Metadata, Viewport } from "next";
import { Unbounded, Manrope, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const unbounded = Unbounded({
  subsets: ["latin", "cyrillic"],
  variable: "--font-unbounded",
  display: "swap",
  weight: ["600", "700"],
});

// Manrope вместо Inter. Inter — шрифт по умолчанию у всех генераторов
// лендингов, и именно он выдаёт шаблонное происхождение сайта. У Manrope
// заметнее геометрия и выше x-height, кириллица полная.
const manrope = Manrope({
  subsets: ["latin", "cyrillic"],
  variable: "--font-body",
  display: "swap",
  weight: ["400", "500", "600", "700"],
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin", "cyrillic"],
  variable: "--font-mono",
  display: "swap",
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  title: "Plink — Комната. Видео. Вместе.",
  description:
    "Синхронный просмотр YouTube, VK Видео, Rutube и ещё одиннадцати сервисов. Чат, реакции, друзья — без расширений. iOS / macOS / Windows / Android.",
  keywords: [
    "совместный просмотр",
    "watch together",
    "синхронный просмотр",
    "plink",
    "видео с друзьями",
    "ios приложение",
    "vk видео",
    "rutube",
    "youtube watch party",
  ],
  authors: [{ name: "Plink" }],
  creator: "Plink",
  publisher: "Plink",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  metadataBase: new URL("https://plink.app"),
  alternates: {
    canonical: "/",
    languages: {
      "ru-RU": "/",
    },
  },
  openGraph: {
    type: "website",
    locale: "ru_RU",
    url: "https://plink.app",
    siteName: "Plink",
    title: "Plink — Совместный просмотр видео с друзьями",
    description:
      "Смотри видео синхронно с друзьями: один кадр, одна пауза, одни эмоции. YouTube, VK Видео, Rutube.",
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "Plink — четыре устройства, один кадр",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Plink — Совместный просмотр видео",
    description:
      "Смотри видео синхронно с друзьями: один кадр, одна пауза, одни эмоции.",
    images: ["/og-image.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  icons: {
    icon: [
      { url: "/favicon-16x16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32x32.png", sizes: "32x32", type: "image/png" },
    ],
    apple: [
      { url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" },
    ],
  },
  manifest: "/site.webmanifest",
};

export const viewport: Viewport = {
  themeColor: "#0B0F10",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="ru"
      className={`${unbounded.variable} ${manrope.variable} ${jetbrainsMono.variable}`}
    >
      <body className="min-h-screen bg-bg text-text-primary antialiased">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded focus:bg-accent focus:px-4 focus:py-2 focus:text-bg focus:font-medium"
        >
          Перейти к содержимому
        </a>
        {children}
      </body>
    </html>
  );
}
