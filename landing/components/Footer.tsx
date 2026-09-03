'use client';

import Link from 'next/link';
import { SUPPORT_EMAIL } from '@/lib/constants';
import PlinkMark from './PlinkMark';

const links = [
  { href: '/terms', label: 'Условия использования' },
  { href: '/privacy', label: 'Конфиденциальность' },
  { href: `mailto:${SUPPORT_EMAIL}`, label: 'Поддержка' },
];

const socials = [
  {
    name: 'Telegram',
    href: 'https://t.me/plinkapp',
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
      </svg>
    ),
  },
  {
    name: 'X (Twitter)',
    href: 'https://x.com/plinkapp',
    icon: (
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
      </svg>
    ),
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-surface-2 bg-surface/30" role="contentinfo">
      <div className="container-main py-16">
        <div className="grid gap-12 md:grid-cols-12">
          {/* Brand */}
          <div className="md:col-span-5">
            <Link
              href="/"
              className="text-display inline-flex items-center gap-2.5 text-2xl font-bold text-text-primary"
              aria-label="Plink"
            >
              <PlinkMark size={30} id="foot" />
              <span className="tracking-[0.18em]">PLINK</span>
            </Link>
            <p className="mt-4 max-w-xs text-sm text-text-secondary">
              Совместный просмотр видео с друзьями. Один кадр, одна пауза, одни эмоции.
            </p>
            <div className="mt-6 flex gap-4">
              {socials.map((social) => (
                <a
                  key={social.name}
                  href={social.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex h-10 w-10 items-center justify-center rounded-lg bg-surface-2 text-text-secondary transition-colors hover:bg-accent hover:text-bg focus:outline-none focus:ring-2 focus:ring-accent"
                  aria-label={social.name}
                >
                  {social.icon}
                </a>
              ))}
            </div>
          </div>

          {/* Links */}
          <div className="md:col-span-3">
            <h3 className="text-sm font-semibold text-text-primary">Документы</h3>
            <ul className="mt-4 space-y-3">
              {links.map((link) => (
                <li key={link.label}>
                  <a
                    href={link.href}
                    className="inline-block py-2 text-sm text-text-secondary transition-colors hover:text-accent focus:outline-none focus:ring-2 focus:ring-accent"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          {/* Contact */}
          <div className="md:col-span-4">
            <h3 className="text-sm font-semibold text-text-primary">Связаться</h3>
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="mt-4 inline-block text-sm text-accent underline decoration-accent/30 underline-offset-4 transition-colors hover:decoration-accent focus:outline-none focus:ring-2 focus:ring-accent"
            >
              {SUPPORT_EMAIL}
            </a>
            <p className="mt-4 text-xs text-text-muted">
              Отвечаем в течение 24 часов.
              <br />
              По-русски и по-английски.
            </p>
          </div>
        </div>

        <div className="mt-16 flex flex-col items-center justify-between gap-4 border-t border-surface-2 pt-8 sm:flex-row">
          <p className="text-xs text-text-muted">
            © {new Date().getFullYear()} Plink. Все права защищены.
          </p>
          <p className="text-xs text-text-muted">Сделано с любовью к совместным просмотрам</p>
        </div>
      </div>
    </footer>
  );
}
