# OpenNews Server

Hono backend with Mastra AI, Drizzle ORM, and structured Pino logging. Runs on Bun.

## Stack

- **Framework**: Hono (middleware, SSE, static file serving)
- **AI**: Mastra v1 (`@mastra/core` as library) + Vercel AI SDK
- **Database**: SQLite via `bun:sqlite` + Drizzle ORM (WAL mode)
- **Logging**: Pino + `hono-pino` middleware + Logdy (dev browser UI)
- **Auth**: JWT cookie + Bearer AUTH_SECRET dual-mode

## Directory Structure

```
src/
├── index.ts            # Server entry point, middleware stack, static serving
├── config.ts           # Zod-validated env config, exported AppConfig
├── model.ts            # LLM model factory: createModel() (single model MVP)
├── routes/
│   ├── auth.ts         # Login, check, logout + auth middleware
│   ├── feed.ts         # GET /api/v1/feed (cursor pagination)
│   ├── article.ts      # GET/POST/DELETE article + SSE streaming
│   ├── settings.ts     # GET/PUT settings (single-row upsert)
│   ├── sources.ts      # CRUD for RSS feeds
│   └── health.ts       # GET /api/health
├── db/
│   ├── index.ts        # Database connection + WAL pragmas
│   ├── schema.ts       # Drizzle schema (all tables)
│   └── migrate.ts      # Migration runner
├── services/
│   ├── ingestion.ts    # Source fetching orchestrator
│   ├── rss.ts          # @extractus/feed-extractor
│   ├── hackernews.ts   # HN API client
│   ├── tavily.ts       # Tavily search client
│   ├── extractor.ts    # ContentExtractor chain (readability → tavily)
│   ├── dedup.ts        # URL normalization + Dice coefficient + ranking
│   ├── headline.ts     # Headline generation (AI SDK generateObject)
│   ├── digest.ts       # Daily digest service (plain async function)
│   └── cron.ts         # croner scheduling
└── mastra/
    ├── index.ts        # Mastra instance (Article Agent only)
    ├── agents/
    │   └── article-agent.ts    # Deep-dive article generation with streaming
    └── tools/
        ├── tavily-search.ts    # Tavily search as Mastra tool
        ├── tavily-extract.ts   # Tavily extract as Mastra tool
        └── fetch-content.ts    # Readability extraction as Mastra tool
```

## Hono Patterns

### Middleware Stack

```typescript
import { Hono } from 'hono';
import { pinoLogger } from 'hono-pino';
import { cors } from 'hono/cors';
import { serveStatic } from 'hono/bun';

const app = new Hono();
app.use(pinoLogger({ pino: logger, http: { reqId: () => crypto.randomUUID() } }));
app.use('/api/*', cors());
```

### Route Groups

```typescript
const api = new Hono();
api.route('/auth', authRoutes);
api.route('/feed', feedRoutes);
// ...
app.route('/api/v1', api);
```

### SSE Streaming (Article Generation)

```typescript
import { streamSSE } from 'hono/streaming';

// For Mastra agent streaming, use toDataStreamResponse():
app.post('/api/v1/article/:topicId/generate', async (c) => {
  const agent = mastra.getAgent('articleGenerator');
  const stream = await agent.stream(prompt);
  return stream.toDataStreamResponse();
});
```

### Static File Serving (Production SPA)

```typescript
app.use('/assets/*', serveStatic({ root: '../web/dist' }));
app.get('*', serveStatic({ root: '../web/dist', path: 'index.html' }));
```

## Mastra Patterns

See `/mastra` skill for comprehensive v1 API reference. Key reminders:

- Import: `@mastra/core` (Mastra), `@mastra/core/agent` (Agent), `@mastra/core/tools` (createTool), `@mastra/core/workflows` (createWorkflow, createStep)
- Tool execute: `async (inputData, context) => { ... }` — NOT `({ context })`
- Structured output: `agent.generate(prompt, { structuredOutput: { schema } })` → `result.object`
- Workflow: `createWorkflow({}).then(step1).then(step2).commit()`

## Drizzle Patterns

### Database Connection

```typescript
import { Database } from 'bun:sqlite';
import { drizzle } from 'drizzle-orm/bun-sqlite';
import * as schema from './schema';

const sqlite = new Database(process.env.DATABASE_PATH ?? './data/open-news.db');
sqlite.run('PRAGMA journal_mode = WAL');
sqlite.run('PRAGMA busy_timeout = 5000');
sqlite.run('PRAGMA synchronous = NORMAL');
sqlite.run('PRAGMA foreign_keys = ON');

export const db = drizzle(sqlite, { schema });
```

### Queries

```typescript
import { eq, desc, lt, and } from 'drizzle-orm';

// Select with joins
const topics = await db.query.dailyTopics.findMany({
  where: and(lt(dailyTopics.date, cursor), tag ? eq(topicTags.tagId, tagId) : undefined),
  orderBy: [desc(dailyTopics.date), desc(dailyTopics.relevanceScore)],
  with: { topicTags: { with: { tag: true } }, topicSources: true },
  limit,
});

// Upsert (single-row settings)
await db.insert(settings).values(data).onConflictDoUpdate({
  target: settings.id,
  set: { ...data, updatedAt: new Date().toISOString() },
});
```

## Auth Pattern

```typescript
// Middleware: cookie-first, bearer-fallback
async function authMiddleware(c, next) {
  const cookie = getCookie(c, 'session');
  if (cookie) {
    // Verify JWT signed with key derived from AUTH_SECRET
    const payload = await verifyJWT(cookie);
    if (payload) return next();
  }
  const bearer = c.req.header('Authorization')?.replace('Bearer ', '');
  if (bearer === config.AUTH_SECRET) return next();
  return c.json({ error: 'Unauthorized' }, 401);
}
```

## Logging

Access request-scoped logger via `c.var.logger` in route handlers (from `hono-pino`).

```typescript
app.get('/api/v1/feed', async (c) => {
  c.var.logger.info({ cursor, tag }, 'Fetching feed');
  // ...
});
```
