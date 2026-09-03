// routes/assets.ts — статика лендинга (шрифты, кадры продукта).
//
// Зачем отдельный роут, а не @fastify/static: у сайта строгий CSP
// (`default-src 'none'`), поэтому внешние CDN и Google Fonts запрещены, а
// свои файлы нужно отдавать с точными заголовками и без обхода каталога.
// Здесь белый список имён — путь из запроса в файловую систему не попадает.
//
// Раскладка: <repo>/backend/assets/** ; в образе — /app/assets/**
// (Dockerfile копирует каталог в runtime-стадию). Резолв через import.meta.url
// одинаково работает и для src/ под tsx, и для dist/ под node.

import type { FastifyInstance, FastifyReply } from 'fastify';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ASSETS_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'assets',
);

/// Белый список: имя файла → (подкаталог, content-type).
/// Всё, чего здесь нет, отдаёт 404 — обхода каталога не существует в принципе.
const FONTS: Record<string, true> = {
  'inter-latin.woff2': true,
  'inter-latin-ext.woff2': true,
  'inter-cyrillic.woff2': true,
  'playfair-italic-latin.woff2': true,
  'playfair-italic-latin-ext.woff2': true,
  'playfair-italic-cyrillic.woff2': true,
};

/// Кадры продукта для лендинга (наполняется по мере добавления файлов).
const SHOTS: Record<string, string> = {};

/// Файлы неизменяемы (при замене меняется имя), поэтому год иммутабельного кэша.
const IMMUTABLE = 'public, max-age=31536000, immutable';

const cache = new Map<string, Buffer>();

async function sendAsset(
  reply: FastifyReply,
  relativePath: string,
  contentType: string,
): Promise<FastifyReply> {
  let body = cache.get(relativePath);
  if (!body) {
    try {
      body = await readFile(path.join(ASSETS_ROOT, relativePath));
    } catch {
      return reply.code(404).type('text/plain; charset=utf-8').send('Not found');
    }
    cache.set(relativePath, body);
  }
  return reply
    .type(contentType)
    .header('Cache-Control', IMMUTABLE)
    .header('X-Content-Type-Options', 'nosniff')
    .send(body);
}

export default async function assetsRoutes(fastify: FastifyInstance) {
  fastify.get<{ Params: { file: string } }>('/assets/fonts/:file', async (req, reply) => {
    const file = req.params.file;
    if (!FONTS[file]) return reply.code(404).type('text/plain; charset=utf-8').send('Not found');
    return sendAsset(reply, path.join('fonts', file), 'font/woff2');
  });

  fastify.get<{ Params: { file: string } }>('/assets/shots/:file', async (req, reply) => {
    const type = SHOTS[req.params.file];
    if (!type) return reply.code(404).type('text/plain; charset=utf-8').send('Not found');
    return sendAsset(reply, path.join('shots', req.params.file), type);
  });
}

/// Экспорт для web.ts: какие шрифты объявлять в @font-face.
export const FONT_FILES = Object.keys(FONTS);
