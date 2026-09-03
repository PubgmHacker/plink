/** @type {import('postcss-load-config').Config} */
// Собственный postcss.config заменяет дефолтный конфиг Next целиком, поэтому
// autoprefixer нужно подключать явно — иначе префиксы не ставятся вовсе.
const config = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};

export default config;
