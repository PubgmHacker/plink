// aiStream.ts — Plink M39 (v2)
//
// Проблемы v1:
//   1. Клиент закрывал экран, а запрос к OpenRouter продолжал гореть токены.
//   2. Нет heartbeat — прокси Railway рвали молчащее SSE-соединение.
//   3. Rate limit считался по IP — под CGNAT мобильного оператора один активный
//      пользователь блокировал всё метро.

import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify'

const OPENROUTER_URL = process.env.OPENROUTER_URL ?? 'https://openrouter.ai/api/v1/chat/completions'
const AI_MODEL = process.env.AI_MODEL ?? 'openai/gpt-4o-mini'

const HEARTBEAT_MS = 15_000
const UPSTREAM_TIMEOUT_MS = 30_000
const MAX_MESSAGE_LEN = 2000
const MAX_MESSAGES = 24

type ChatMessage = { role: 'system' | 'user' | 'assistant'; content: string }

interface StreamBody {
  messages: ChatMessage[]
  roomId?: string
}

export async function aiStreamRoutes(fastify: FastifyInstance) {
  fastify.post<{ Body: StreamBody }>('/ai/stream', {
    config: {
      rateLimit: {
        max: 30,
        timeWindow: '1 minute',
        // Ключ — идентификатор пользователя, IP — только для анонимов.
        keyGenerator: (req: FastifyRequest) => (req as any).user?.id ?? req.ip,
      },
    },
  }, async (request: FastifyRequest<{ Body: StreamBody }>, reply: FastifyReply) => {
    const raw = Array.isArray(request.body?.messages) ? request.body.messages : []

    if (raw.length === 0) {
      return reply.code(400).send({ error: 'messages_required' })
    }

    const messages: ChatMessage[] = raw
      .slice(-MAX_MESSAGES)
      .filter((m) => m && typeof m.content === 'string' && m.content.trim().length > 0)
      .map((m) => ({
        role: m.role === 'assistant' || m.role === 'system' ? m.role : 'user',
        content: m.content.slice(0, MAX_MESSAGE_LEN),
      }))

    if (messages.length === 0) {
      return reply.code(400).send({ error: 'messages_empty' })
    }

    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    })

    const controller = new AbortController()
    let closed = false
    let finished = false

    const onClose = () => {
      closed = true
      controller.abort()
    }
    // Главный фикс: ушёл клиент — прекращаем платить за токены.
    request.raw.once('close', onClose)

    const heartbeat = setInterval(() => {
      if (!closed && !finished) {
        // Комментарий SSE — клиент его игнорирует, прокси видит трафик.
        reply.raw.write(': ping\n\n')
      }
    }, HEARTBEAT_MS)

    const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS)

    const send = (payload: unknown) => {
      if (!closed) reply.raw.write(`data: ${JSON.stringify(payload)}\n\n`)
    }

    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined

    try {
      const upstream = await fetch(OPENROUTER_URL, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${process.env.OPENROUTER_API_KEY ?? ''}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': process.env.PUBLIC_ORIGIN ?? 'https://plink.app',
          'X-Title': 'Plink',
        },
        body: JSON.stringify({ model: AI_MODEL, messages, stream: true, max_tokens: 900 }),
      })

      clearTimeout(timeout)

      if (!upstream.ok || !upstream.body) {
        send({ error: 'upstream_failed', message: 'ИИ не ответил. Попробуйте ещё раз.' })
        finished = true
        return
      }

      reader = upstream.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (!closed) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''

        for (const line of lines) {
          const trimmed = line.trim()
          if (!trimmed.startsWith('data:')) continue
          const payload = trimmed.slice(5).trim()

          if (payload === '[DONE]') {
            finished = true
            break
          }
          if (!closed) reply.raw.write(`data: ${payload}\n\n`)
        }

        if (finished) break
      }

      if (!closed) reply.raw.write('data: [DONE]\n\n')
      finished = true
    } catch (error: any) {
      clearTimeout(timeout)
      if (error?.name !== 'AbortError' && !closed) {
        send({ error: 'stream_failed', message: 'Поток прервался. Попробуйте ещё раз.' })
      }
      request.log.warn({ err: error }, 'ai stream failed')
    } finally {
      clearInterval(heartbeat)
      clearTimeout(timeout)
      request.raw.removeListener('close', onClose)
      // Без cancel() соединение с upstream остаётся висеть и течёт память.
      try { await reader?.cancel() } catch { /* уже закрыт */ }
      if (!reply.raw.writableEnded) reply.raw.end()
    }
  })
}
