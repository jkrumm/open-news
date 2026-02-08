// OpenNews server entry point

import { createLogger } from '@open-news/shared';
import { Hono } from 'hono';
import { pinoLogger } from 'hono-pino';

const logger = createLogger('server');

const app = new Hono();

// Pino request logger middleware - adds structured logging with requestId, responseTime, etc.
app.use(
  '*',
  pinoLogger({
    pino: createLogger('http'),
    http: {
      reqId: () => crypto.randomUUID(),
      responseTime: true,
    },
  }),
);

// Health check endpoint
app.get('/api/health', (c) => {
  c.var.logger.info('Health check');
  return c.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
  });
});

const PORT = Number.parseInt(process.env.PORT ?? '3000', 10);

logger.info({ port: PORT }, 'Starting OpenNews server');

export default {
  port: PORT,
  fetch: app.fetch,
};
