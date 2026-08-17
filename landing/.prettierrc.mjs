// landing/.prettierrc.mjs — the root Prettier config plus the Tailwind plugin.
//
// Prettier has no `extends`, and it does not merge configs across directories:
// for any given file the nearest config wins outright. So the shared settings
// are imported from the repository root and spread here, rather than copied —
// copies drift, and a formatter that disagrees with itself between packages
// produces a diff every time someone saves a file in the other package.
//
// Why this file exists at all: prettier-plugin-tailwindcss sorts class strings
// into Tailwind's own order, which makes `className` diffs readable instead of
// arbitrary. The plugin is a dependency of this package only, and Prettier
// resolves a bare plugin name against the *working directory* rather than
// against the config that names it — so `plugins: ['prettier-plugin-tailwindcss']`
// works when run from landing/ and fails with `Cannot find package …` when run
// from the repository root, which is how `make format` and CI run it. Resolving
// the path here, relative to this file, makes it work from either.

import { createRequire } from 'node:module';

import root from '../.prettierrc.json' with { type: 'json' };

const require = createRequire(import.meta.url);

// The root config's own `landing/**` override is gone; the plugin is declared
// here instead. Everything else — print width, quotes, trailing commas — comes
// from the root and must not be restated.
export default {
  ...root,
  plugins: [require.resolve('prettier-plugin-tailwindcss')],
};
