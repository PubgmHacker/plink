import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        bg: '#0A0C0D',
        surface: '#161B1E',
        'surface-2': '#2A3233',
        accent: '#FFB800',
        'accent-dim': '#D99A00',
        text: {
          primary: '#F0F2F1',
          secondary: '#9A9E9C',
          muted: '#B0B7B3',
        },
        sync: '#FFB800',
      },
      fontFamily: {
        display: ['var(--font-unbounded)', 'sans-serif'],
        body: ['var(--font-body)', 'sans-serif'],
        mono: ['var(--font-mono)', 'monospace'],
        serif: ['var(--font-serif-accent)', 'Georgia', 'serif'],
      },
      fontSize: {
        xs: ['0.75rem', { lineHeight: '1rem' }],
        sm: ['0.875rem', { lineHeight: '1.375rem' }],
        base: ['1rem', { lineHeight: '1.625rem' }],
        lg: ['1.125rem', { lineHeight: '1.75rem' }],
        xl: ['1.25rem', { lineHeight: '1.75rem' }],
        '2xl': ['1.5rem', { lineHeight: '1.875rem' }],
        '3xl': ['1.75rem', { lineHeight: '2rem' }],
        '4xl': ['2.25rem', { lineHeight: '2.25rem' }],
        '5xl': ['3rem', { lineHeight: '3rem' }],
        '6xl': ['4rem', { lineHeight: '4rem' }],
        '7xl': ['5.5rem', { lineHeight: '5.5rem' }],
      },
      spacing: {
        'section-sm': '5rem',
        'section-md': '7.5rem',
        'section-lg': '10rem',
      },
      animation: {
        'fade-up': 'fadeUp 0.6s cubic-bezier(0.32, 0.72, 0, 1) forwards',
        'fade-in': 'fadeIn 0.4s cubic-bezier(0.32, 0.72, 0, 1) forwards',
        float: 'float 6s ease-in-out infinite',
      },
      keyframes: {
        fadeUp: {
          '0%': { opacity: '0', transform: 'translateY(24px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-8px)' },
        },
      },
      transitionTimingFunction: {
        smooth: 'cubic-bezier(0.32, 0.72, 0, 1)',
      },
    },
  },
  plugins: [],
};
export default config;
