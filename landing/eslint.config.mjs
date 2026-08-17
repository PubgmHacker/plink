// landing/eslint.config.mjs — ESLint flat config for the marketing site.
//
// Replaces .eslintrc.json, which ESLint 10 does not read at all. That file was
// inert: `next lint` reported no problems because no rules were loaded, not
// because there were none.
//
// Why this composes the plugins directly instead of extending eslint-config-next
// ────────────────────────────────────────────────────────────────────────────
// eslint-config-next@16.3.0 is the obvious thing to extend, and it does not run
// under ESLint 10. It bundles an ESLint-9-era toolchain — eslint-plugin-react
// 7.37.5, which calls `context.getFilename()` (removed in ESLint 10), and an
// import-resolver chain whose scope manager predates `scopeManager.addGlobals`.
// Either one throws before a single line is linted. Its peer range still claims
// `eslint: ">=9.0.0"`, so npm installs the combination without complaint.
//
// The alternative was pinning this package to eslint@9 while the backend runs
// eslint@10. Two major versions of the same linter in one repository means two
// rule sets, two sets of release notes, and a rule that exists on one side of
// the monorepo and not the other. Composing the plugins ourselves keeps both
// packages on the same ESLint and costs one screen of configuration.
//
// What we get from Next either way: @next/eslint-plugin-next ships the flat
// config directly (`configs['core-web-vitals']`) and is parser-free — 22 rules,
// no transitive toolchain. Nothing is lost.
//
// What we give up: the react and jsx-a11y rule sets eslint-config-next also
// bundles. react-hooks is re-added below because its two rules catch real bugs;
// accessibility is checked in review rather than mechanically. That is a gap,
// stated rather than hidden.

import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import nextPlugin from '@next/eslint-plugin-next';
import reactHooks from 'eslint-plugin-react-hooks';

export default tseslint.config(
  // ── What is not linted ───────────────────────────────────────────────────
  {
    ignores: [
      '.next/**',
      'node_modules/**',
      'out/**',
      'public/**',
      'next-env.d.ts',
      'tsconfig.tsbuildinfo',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  // ── Next.js ──────────────────────────────────────────────────────────────
  // core-web-vitals is the base Next config plus the rules that cost a
  // Lighthouse score: unsized images, synchronous scripts, fonts that block
  // paint. This is a landing page whose entire job is loading fast, so those
  // are not advice.
  nextPlugin.configs['core-web-vitals'],

  // ── React hooks ──────────────────────────────────────────────────────────
  {
    files: ['**/*.{jsx,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: {
      // Not a style rule. A conditional hook call corrupts React's hook
      // ordering and fails at runtime, in production, on the second render.
      'react-hooks/rules-of-hooks': 'error',

      // Warn, not error: the animation components below deliberately omit
      // deps to run an effect once on mount. Each of those is a judgement
      // call worth seeing in the output, not worth blocking a build over.
      'react-hooks/exhaustive-deps': 'warn',
    },
  },

  // ── Project rules ────────────────────────────────────────────────────────
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    rules: {
      // This page renders on the server and ships no logging of its own; a
      // console call is leftover debugging that reaches a visitor's browser.
      'no-console': 'error',

      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-var': 'error',
      'prefer-const': 'error',

      // Next's <Image> handles sizing, format negotiation, and lazy loading.
      // A raw <img> on a page measured by Core Web Vitals is a regression, so
      // this is raised from the plugin's default 'warn'.
      '@next/next/no-img-element': 'error',

      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
        },
      ],
    },
  },

  // ── Config files ─────────────────────────────────────────────────────────
  // Build configuration runs in Node, before any of the above applies.
  {
    files: ['*.config.{js,mjs,ts}', 'tailwind.config.ts'],
    rules: {
      'no-console': 'off',
    },
  },
);
