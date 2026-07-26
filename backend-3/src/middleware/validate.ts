// src/middleware/validate.ts — Zod validation для всех input
import { ZodSchema, ZodError } from 'zod';
import { FastifyRequest, FastifyReply } from 'fastify';

export function validateBody(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      request.body = schema.parse(request.body);
    } catch (e) {
      if (e instanceof ZodError) {
        return reply.status(400).send({
          error: 'Validation failed',
          details: e.errors.map(err => ({
            field: err.path.join('.'),
            message: err.message,
          })),
        });
      }
      return reply.status(400).send({ error: 'Invalid input' });
    }
  };
}

export function validateQuery(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      (request as any).query = schema.parse(request.query);
    } catch (e) {
      if (e instanceof ZodError) {
        return reply.status(400).send({
          error: 'Query validation failed',
          details: e.errors.map(err => ({
            field: err.path.join('.'),
            message: err.message,
          })),
        });
      }
    }
  };
}

export function validateParams(schema: ZodSchema) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      (request as any).params = schema.parse(request.params);
    } catch (e) {
      if (e instanceof ZodError) {
        return reply.status(400).send({
          error: 'Params validation failed',
          details: e.errors.map(err => ({
            field: err.path.join('.'),
            message: err.message,
          })),
        });
      }
    }
  };
}
