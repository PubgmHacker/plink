// src/middleware/validate.ts — Zod validation для всех input
//
// Ревью 02.08.2026: раньше только validateBody гарантированно отвечал 400.
// В validateQuery и validateParams ветка «ошибка не ZodError» ничего не
// возвращала, а хук, завершившийся без ответа и без брошенной ошибки,
// для Fastify означает «проверка пройдена» — запрос уходил в хендлер с
// непроверенными query/params. Ошибка валидатора никогда не должна
// означать «пропустить»: теперь все три хелпера fail-closed.
import { ZodSchema, ZodError } from 'zod';
import { FastifyRequest, FastifyReply } from 'fastify';

/// Общий ответ на проваленную валидацию. Детали отдаются только для
/// ZodError — в них нет ничего, кроме имён полей и требований схемы.
/// Любая другая ошибка наружу не подробностится: в неё может утечь
/// внутреннее сообщение из refine/transform.
function rejectInvalid(
  reply: FastifyReply,
  request: FastifyRequest,
  where: 'body' | 'query' | 'params',
  error: unknown,
) {
  if (error instanceof ZodError) {
    return reply.status(400).send({
      error: where === 'body' ? 'Validation failed' : `${where === 'query' ? 'Query' : 'Params'} validation failed`,
      details: error.errors.map((err) => ({
        field: err.path.join('.'),
        message: err.message,
      })),
    });
  }

  // Не ZodError — это сбой самого валидатора. Раньше такое молча пропускалось;
  // логируем, чтобы такие случаи были видны, а не превращались в тихую дыру.
  request.log?.error({ err: error, where }, '[validate] валидатор упал не на ZodError');
  return reply.status(400).send({ error: 'Invalid input' });
}

export function validateBody(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      request.body = schema.parse(request.body);
    } catch (e) {
      return rejectInvalid(reply, request, 'body', e);
    }
  };
}

export function validateQuery(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      (request as any).query = schema.parse(request.query);
    } catch (e) {
      return rejectInvalid(reply, request, 'query', e);
    }
  };
}

export function validateParams(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      (request as any).params = schema.parse(request.params);
    } catch (e) {
      return rejectInvalid(reply, request, 'params', e);
    }
  };
}
