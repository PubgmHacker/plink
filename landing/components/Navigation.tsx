"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { APP_STORE_URL } from "@/lib/constants";

const links = [
  { href: "#how-it-works", label: "Как работает" },
  { href: "#features", label: "Возможности" },
  { href: "#comparison", label: "Сравнение" },
  { href: "#pricing", label: "Тарифы" },
  { href: "#faq", label: "FAQ" },
];

export default function Navigation() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <motion.header
      initial={{ y: -100 }}
      animate={{ y: 0 }}
      transition={{ duration: 0.6, ease: [0.32, 0.72, 0, 1] }}
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-500 ${
        scrolled
          ? "border-b border-surface-2 bg-bg/80 backdrop-blur-xl"
          : "bg-transparent"
      }`}
    >
      <nav className="container-main flex h-20 items-center justify-between">
        {/* Logo */}
        <a
          href="#"
          className="text-display text-2xl font-bold tracking-tight text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
          aria-label="Plink — на главную"
        >
          Plink
        </a>

        {/* Desktop nav */}
        <ul className="hidden items-center gap-8 lg:flex">
          {links.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className="text-sm font-medium text-text-secondary transition-colors hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-accent"
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="flex items-center gap-4">
          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="hidden rounded-lg bg-surface-2 px-5 py-2.5 text-sm font-medium text-text-primary transition-all hover:bg-accent hover:text-bg focus:outline-none focus:ring-2 focus:ring-accent sm:inline-block"
          >
            Скачать
          </a>

          {/* Mobile menu button */}
          <button
            onClick={() => setMobileOpen(!mobileOpen)}
            className="flex h-10 w-10 items-center justify-center rounded-lg text-text-primary lg:hidden"
            aria-expanded={mobileOpen}
            aria-label="Меню"
          >
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
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
            animate={{ opacity: 1, height: "auto" }}
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
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="block rounded-lg bg-accent px-4 py-3 text-center text-base font-semibold text-bg"
                >
                  Скачать в App Store
                </a>
              </li>
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.header>
  );
}
