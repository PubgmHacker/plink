'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { motion, AnimatePresence } from 'framer-motion';
import PlinkMark from './PlinkMark';
import StoreCta from './StoreCta';

const links = [
  { href: '#how-it-works', label: 'Как работает' },
  { href: '#features', label: 'Возможности' },
  { href: '#ecosystem', label: 'Экосистема' },
  { href: '#pricing', label: 'Тарифы' },
  { href: '#faq', label: 'FAQ' },
];

export default function Navigation() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <motion.header
      initial={{ y: -100 }}
      animate={{ y: 0 }}
      transition={{ duration: 0.6, ease: [0.32, 0.72, 0, 1] }}
      className="fixed inset-x-0 top-0 z-50 px-4 pt-3 sm:px-6"
    >
      <nav
        className={`container-main flex items-center justify-between rounded-full transition-all duration-500 ${
          scrolled ? 'liquid-glass liquid-glass-strong h-16 !px-5 md:!px-6' : 'h-16 !px-5 md:!px-6'
        }`}
      >
        {/* Logo */}
        <Link
          href="/"
          className="text-display flex items-center gap-2.5 text-2xl font-bold tracking-tight text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
          aria-label="Plink — на главную"
        >
          <PlinkMark size={30} id="nav" />
          <span className="tracking-[0.18em]">PLINK</span>
        </Link>

        {/* Desktop nav */}
        <ul className="hidden items-center gap-8 lg:flex">
          {links.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className="inline-block px-2 py-2 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="flex items-center gap-4">
          <StoreCta
            label="Скачать"
            className="liquid-glass liquid-glass-interactive hidden rounded-full px-5 py-2.5 text-sm font-semibold text-text-primary transition-all duration-300 hover:-translate-y-0.5 focus:outline-none focus:ring-2 focus:ring-accent sm:inline-block"
          />

          {/* Mobile menu button */}
          <button
            onClick={() => setMobileOpen(!mobileOpen)}
            className="flex h-10 w-10 items-center justify-center rounded-lg text-text-primary lg:hidden"
            aria-expanded={mobileOpen}
            aria-label="Меню"
          >
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              {mobileOpen ? (
                <path d="M18 6L6 18M6 6l12 12" />
              ) : (
                <path d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
        </div>
      </nav>

      {/* Mobile menu */}
      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.3, ease: [0.32, 0.72, 0, 1] }}
            className="border-b border-surface-2 bg-bg/95 backdrop-blur-xl lg:hidden"
          >
            <ul className="container-main space-y-1 py-4">
              {links.map((link) => (
                <li key={link.href}>
                  <a
                    href={link.href}
                    onClick={() => setMobileOpen(false)}
                    className="block rounded-lg px-4 py-3 text-base font-medium text-text-secondary transition-colors hover:bg-surface hover:text-text-primary"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
              <li className="pt-2">
                <StoreCta className="block rounded-lg bg-accent px-4 py-3 text-center text-base font-semibold text-bg" />
              </li>
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.header>
  );
}
