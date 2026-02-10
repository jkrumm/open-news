# OpenNews - Technical Architecture

> System design, data model, API, frontend, and infrastructure.
> For architectural decisions, see [`DECISIONS.md`](./DECISIONS.md).
> For the news pipeline (source discovery, extraction, research tools), see [`PIPELINE.md`](./PIPELINE.md).
> For AI agents, prompts, compression, and streaming, see [`AI_STACK.md`](./AI_STACK.md).

---

## 1. Monorepo Structure

```
open-news/
├── apps/
│   ├── server/                    # Hono backend + Mastra
│   │   ├── src/
│   │   │   ├── index.ts           # Server entry point
│   │   │   ├── config.ts          # Environment config + validation
│   │   │   ├── model.ts           # LLM model factory
│   │   │   ├── logger.ts          # Pino logger instance (child of shared factory)
│   │   │   ├── routes/
│   │   │   │   ├── api.ts         # REST API router
│   │   │   │   ├── auth.ts        # Auth middleware
│   │   │   │   ├── feed.ts        # Feed endpoints
│   │   │   │   ├── settings.ts    # Settings CRUD
│   │   │   │   ├── article.ts     # Article generation + streaming
│   │   │   │   └── health.ts      # Health check
│   │   │   ├── db/
│   │   │   │   ├── index.ts       # Database connection
│   │   │   │   ├── schema.ts      # Drizzle schema
│   │   │   │   └── migrate.ts     # Migration runner
│   │   │   ├── services/
│   │   │   │   ├── adapters/
│   │   │   │   │   ├── source/         # Stage 1: SourceAdapter implementations
│   │   │   │   │   │   ├── rss.ts
│   │   │   │   │   │   ├── hackernews.ts
│   │   │   │   │   │   └── tavily-search.ts
│   │   │   │   │   ├── extractor/      # Stage 2: ContentExtractor implementations
│   │   │   │   │   │   ├── readability.ts
│   │   │   │   │   │   └── tavily-extract.ts
│   │   │   │   │   └── registry.ts     # buildSourceAdapters, buildExtractorChain
│   │   │   │   ├── ingestion.ts   # Source fetching orchestrator
│   │   │   │   ├── dedup.ts       # Deduplication + ranking
│   │   │   │   ├── headline.ts    # Headline generation (AI SDK generateObject)
│   │   │   │   ├── digest.ts      # Daily digest orchestrator (plain async fn)
│   │   │   │   └── cron.ts        # Cron job setup
│   │   │   └── mastra/
│   │   │       ├── index.ts       # Mastra instance (Article Agent only)
│   │   │       ├── agents/
│   │   │       │   └── article-agent.ts     # Generates deep-dive articles
│   │   │       └── tools/
│   │   │           ├── tavily-search.ts     # Tavily search tool
│   │   │           ├── tavily-extract.ts    # Tavily extract tool
│   │   │           └── fetch-content.ts     # Content extraction tool
│   │   ├── drizzle.config.ts
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── web/                       # React SPA
│       ├── src/
│       │   ├── main.tsx           # React entry
│       │   ├── App.tsx            # Router setup
│       │   ├── routes/
│       │   │   ├── Feed.tsx       # Daily feed page
│       │   │   ├── Article.tsx    # Deep-dive article page
│       │   │   ├── Settings.tsx   # Settings page
│       │   │   └── Login.tsx      # Login page
│       │   ├── components/
│       │   │   ├── TopicCard.tsx   # Single topic headline card
│       │   │   ├── DaySection.tsx  # Group of topics for one day
│       │   │   ├── TagFilter.tsx   # Tag filter bar
│       │   │   ├── ArticleView.tsx # Streaming article renderer
│       │   │   ├── SourceChip.tsx  # Source attribution chip
│       │   │   └── SettingsForm.tsx # Preferences form
│       │   ├── hooks/
│       │   │   ├── use-feed.ts    # Feed data fetching
│       │   │   ├── use-settings.ts # Settings CRUD
│       │   │   └── use-auth.ts    # Auth state
│       │   ├── lib/
│       │   │   ├── api.ts         # API client (fetch wrapper)
│       │   │   └── types.ts       # Re-export shared types
│       │   └── styles/
│       │       └── globals.css    # Tailwind imports + custom styles
│       ├── index.html
│       ├── vite.config.ts
│       ├── package.json
│       └── tsconfig.json
├── packages/
│   └── shared/                    # Shared types + logger
│       ├── src/
│       │   ├── index.ts
│       │   ├── types.ts           # API types, domain models
│       │   └── logger.ts          # Pino logger factory (shared config/schema)
│       ├── package.json
│       └── tsconfig.json
├── biome.json                     # Root Biome config
├── tsconfig.json                  # Root TS config (project references)
├── package.json                   # Workspace root
├── bun.lock
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .github/
│   └── workflows/
│       └── ci.yml
└── docs/
    ├── PRD.md                     # Product requirements + roadmap
    ├── ARCHITECTURE.md            # This file
    ├── DECISIONS.md               # ADRs + decision log
    ├── PIPELINE.md                # Pipeline: source discovery + extraction
    ├── AI_STACK.md                # AI: agents, prompts, compression, streaming
    └── TASKS.md                   # Implementation task breakdown
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container                          │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Hono Server (Bun)                       │    │
│  │                                                      │    │
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  │    │
│  │  │ Static   │  │  REST API    │  │  Streaming   │  │    │
│  │  │ Files    │  │  /api/v1/*   │  │  Endpoints   │  │    │
│  │  │ (React)  │  │              │  │  (SSE)       │  │    │
│  │  └──────────┘  └──────┬───────┘  └──────┬───────┘  │    │
│  │                       │                  │          │    │
│  │  ┌────────────────────┴──────────────────┴──────┐   │    │
│  │  │              Mastra (Library)                  │   │    │
│  │  │  ┌────────────┐  ┌────────┐                   │   │    │
│  │  │  │  Article   │  │ Tools  │                   │   │    │
│  │  │  │  Agent     │  │        │                   │   │    │
│  │  │  └────────────┘  └────────┘                   │   │    │
│  │  │  ┌────────────────────────────────────────┐   │   │    │
│  │  │  │  Daily Digest Service                   │   │   │    │
│  │  │  └────────────────────────────────────────┘   │   │    │
│  │  └───────────────────────────────────────────────┘   │    │
│  │                       │                              │    │
│  │  ┌────────────────────┴──────────────────────────┐   │    │
│  │  │         Services Layer                         │   │    │
│  │  │  RSS Parser │ HN Client │ Tavily │ Extractor  │   │    │
│  │  │  Dedup      │ Cron      │                      │   │    │
│  │  └────────────────────┬──────────────────────────┘   │    │
│  │                       │                              │    │
│  │  ┌────────────────────┴──────────────────────────┐   │    │
│  │  │         SQLite (bun:sqlite + Drizzle)          │   │    │
│  │  └───────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Volume: /app/data/ (SQLite DB + generated content)          │
└─────────────────────────────────────────────────────────────┘
```

### Data Flows

For detailed data flow diagrams, see:
- **Daily ingestion pipeline**: [`PIPELINE.md`](./PIPELINE.md) §Data Flow
- **Article generation (Gather → Compress → Synthesize)**: [`AI_STACK.md`](./AI_STACK.md) §1

---

## 2. Data Model

### SQLite Schema (Drizzle)

```typescript
// packages/shared/src/types.ts - Source types enum
export const SOURCE_TYPES = ['rss', 'hackernews', 'tavily', 'exa', 'perplexity', 'serper', 'gnews'] as const;
export type SourceType = typeof SOURCE_TYPES[number];

// apps/server/src/db/schema.ts

// ─── User Settings (single row) ───────────────────────────
export const settings = sqliteTable('settings', {
  id: integer('id').primaryKey().default(1),
  // Personal profile
  displayName: text('display_name').notNull().default(''),
  background: text('background').notNull().default(''),        // e.g. "Senior Full-Stack Developer"
  interests: text('interests').notNull().default(''),          // free-text description
  newsStyle: text('news_style').notNull().default('concise'),  // 'concise' | 'detailed' | 'technical'
  language: text('language').notNull().default('en'),          // output language
  timezone: text('timezone').notNull().default('Europe/Berlin'),
  // Topics of interest (JSON array of strings)
  topics: text('topics', { mode: 'json' }).notNull().default('[]'),
  // Tavily search queries (JSON array of strings)
  searchQueries: text('search_queries', { mode: 'json' }).notNull().default('[]'),
  updatedAt: text('updated_at').notNull().$defaultFn(() => new Date().toISOString()),
});

// ─── Feed Sources ─────────────────────────────────────────
export const sources = sqliteTable('sources', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  url: text('url').notNull().unique(),
  type: text('type').notNull(),               // 'rss' | 'hackernews' | 'tavily'
  enabled: integer('enabled', { mode: 'boolean' }).notNull().default(true),
  // RSS-specific
  etag: text('etag'),                          // for conditional fetching
  lastModified: text('last_modified'),         // for conditional fetching
  lastFetchedAt: text('last_fetched_at'),
  createdAt: text('created_at').notNull().$defaultFn(() => new Date().toISOString()),
});

// ─── Raw Articles (scraped from sources) ──────────────────
export const rawArticles = sqliteTable('raw_articles', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  sourceId: integer('source_id').references(() => sources.id),
  externalId: text('external_id'),             // HN story ID, RSS guid, etc.
  title: text('title').notNull(),
  url: text('url').notNull(),
  urlNormalized: text('url_normalized').notNull().unique(), // for dedup
  content: text('content'),                    // extracted full text (nullable, stored in DB)
  snippet: text('snippet'),                    // short excerpt
  author: text('author'),
  score: integer('score'),                     // HN score, null for RSS
  publishedAt: text('published_at'),
  scrapedAt: text('scraped_at').notNull().$defaultFn(() => new Date().toISOString()),
  scrapedDate: text('scraped_date').notNull(), // YYYY-MM-DD for daily grouping
});

// ─── Daily Topics (AI-grouped headlines) ──────────────────
// Topic types: 'hot' = main stories of the day, 'normal' = regular grouped topics,
// 'standalone' = individually interesting articles (guides, tutorials, etc.) not grouped into a topic
export const dailyTopics = sqliteTable('daily_topics', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  date: text('date').notNull(),                // YYYY-MM-DD
  topicType: text('topic_type').notNull().default('normal'), // 'hot' | 'normal' | 'standalone'
  headline: text('headline').notNull(),        // AI-generated headline
  summary: text('summary').notNull(),          // AI-generated summary (2-3 sentences)
  relevanceScore: real('relevance_score').notNull().default(0), // 0-1, AI-scored based on user interests
  sourceCount: integer('source_count').notNull().default(1),
  createdAt: text('created_at').notNull().$defaultFn(() => new Date().toISOString()),
});

// ─── Tags ─────────────────────────────────────────────────
export const tags = sqliteTable('tags', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull().unique(),       // e.g. 'ai', 'typescript', 'finance'
  color: text('color'),                        // optional hex color (deferred, null for MVP)
});

// ─── Topic <-> Tag (many-to-many) ─────────────────────────
export const topicTags = sqliteTable('topic_tags', {
  topicId: integer('topic_id').notNull().references(() => dailyTopics.id, { onDelete: 'cascade' }),
  tagId: integer('tag_id').notNull().references(() => tags.id, { onDelete: 'cascade' }),
});

// ─── Topic <-> Raw Article (many-to-many) ─────────────────
export const topicSources = sqliteTable('topic_sources', {
  topicId: integer('topic_id').notNull().references(() => dailyTopics.id, { onDelete: 'cascade' }),
  rawArticleId: integer('raw_article_id').notNull().references(() => rawArticles.id, { onDelete: 'cascade' }),
});

// ─── Generated Articles (cached deep-dives) ──────────────
export const generatedArticles = sqliteTable('generated_articles', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  topicId: integer('topic_id').notNull().references(() => dailyTopics.id, { onDelete: 'cascade' }).unique(),
  content: text('content').notNull(),          // markdown (stored in DB)
  generatedAt: text('generated_at').notNull().$defaultFn(() => new Date().toISOString()),
});
```

### Indexes

```typescript
export const rawArticlesDateIdx = index('raw_articles_date_idx').on(rawArticles.scrapedDate);
export const rawArticlesUrlIdx = uniqueIndex('raw_articles_url_idx').on(rawArticles.urlNormalized);
export const dailyTopicsDateIdx = index('daily_topics_date_idx').on(dailyTopics.date);
export const topicTagsTopicIdx = index('topic_tags_topic_idx').on(topicTags.topicId);
export const topicSourcesTopicIdx = index('topic_sources_topic_idx').on(topicSources.topicId);
```

---

## 3. API Design

### Authentication

Simple shared-secret authentication:

```
AUTH_SECRET=your-secret-here  # environment variable
```

**Login flow**:
1. POST `/api/v1/auth/login` with `{ secret: "..." }`
2. Server validates against `AUTH_SECRET`
3. Returns HTTP-only secure cookie with a JWT (signed with key derived from `AUTH_SECRET`, no expiry)
4. All `/api/v1/*` routes require valid auth
5. GET `/api/v1/auth/check` returns 200 if authenticated, 401 if not

**JWT signing key**: Derived deterministically from `AUTH_SECRET` (e.g. HMAC-SHA256 with a static salt). This ensures JWTs survive server restarts without storing state. No token expiry -- single-user app, session lives forever.

**Dual auth**: Support both Cookie (for the web SPA) and `Authorization: Bearer <AUTH_SECRET>` header (for external API consumers like Glance Dashboard, Obsidian daily notes). Middleware checks cookie first, falls back to bearer header (compared directly against `AUTH_SECRET`). The shared secret is the single source of truth for authentication.

### REST Endpoints

```
# Auth
POST   /api/v1/auth/login          { secret: string }
GET    /api/v1/auth/check           → { authenticated: boolean }
POST   /api/v1/auth/logout

# Settings
GET    /api/v1/settings             → Settings
PUT    /api/v1/settings             { ...partial settings }

# Sources (RSS feeds)
GET    /api/v1/sources              → Source[]
POST   /api/v1/sources              { name, url, type }
PUT    /api/v1/sources/:id          { ...partial source }
DELETE /api/v1/sources/:id

# Feed (daily topics) — cursor-based pagination required from day one
GET    /api/v1/feed                 → { days: DayWithTopics[], nextCursor?: string }
       ?cursor=2026-02-07           # pagination by date (exclusive, returns days before cursor)
       &limit=3                     # days to return (default: 3)
       &tag=ai                      # optional tag filter

# Tags
GET    /api/v1/tags                 → Tag[]

# Article (deep-dive)
GET    /api/v1/article/:topicId     → { cached: boolean, content?: string }
POST   /api/v1/article/:topicId/generate  → SSE stream (markdown tokens)
DELETE /api/v1/article/:topicId/cache     # invalidate cache (refresh)

# Admin
POST   /api/v1/admin/trigger-digest  # manually trigger daily aggregation
GET    /api/v1/admin/status          → { lastDigest, articleCount, ... }

# Health
GET    /api/health                   → { status: 'ok', timestamp }
```

### SSE Streaming (Article Generation)

The article generation endpoint uses Server-Sent Events. Article generation is one-shot (not conversational), so we use `agent.stream()` with `toDataStreamResponse()` on the server and `useCompletion` on the client (not `useChat`, which is for multi-turn conversation). See [`AI_STACK.md`](./AI_STACK.md) §6 Workflow 2 for the full Gather → Compress → Synthesize flow.

```typescript
// Server (apps/server/src/routes/article.ts)
article.post('/:topicId/generate', async (c) => {
  const topicId = c.req.param('topicId');
  const topic = await getTopicWithSources(topicId);
  const settings = await getSettings();

  // Phase B: Compress sources in parallel (AI SDK generateObject per source)
  const compressed = await Promise.all(
    topic.sources.map((source) => compressSource(source))
  );

  // Phase C: Synthesize with streaming (Mastra Article Agent)
  const agent = mastra.getAgent('articleGenerator');
  const stream = await agent.stream(buildSynthesisPrompt(topic, compressed, settings));

  return stream.toDataStreamResponse();
});
```

```typescript
// Client (apps/web/src/routes/Article.tsx)
import { useCompletion } from '@ai-sdk/react';

function ArticlePage({ topicId }: { topicId: string }) {
  const { completion, isLoading, complete } = useCompletion({
    api: `/api/v1/article/${topicId}/generate`,
  });

  // completion is the streamed text (markdown), rendered with streamdown
  // complete() triggers the generation
}
```

---

## 4. Frontend Design

### Pages

**Login (`/login`)**
- Simple password input
- Posts to `/api/v1/auth/login`
- Redirects to `/` on success

**Feed (`/`)**
- Header with app name, tag filter bar, settings link
- Infinite scroll feed grouped by day
- Each day section: date header + topic cards
- Topic card: headline, summary, source count, tags, relevance indicator
- Topic types: 'hot' topics displayed prominently, 'normal' topics in standard layout, 'standalone' articles shown as individual items
- Click card -> navigate to `/article/:topicId`
- Tag filter bar: clickable tag pills, toggleable, filters feed

**Article (`/article/:topicId`)**
- Back button to feed
- Topic headline + metadata (date, source count, tags)
- If cached: render markdown immediately
- If not cached: show loading state, POST to generate, stream markdown in real-time
- Refresh button: invalidates cache, regenerates
- Source list at the bottom (all grouped raw articles with links)
- Rendered markdown with `streamdown` (Vercel's AI-streaming markdown renderer, drop-in replacement for `react-markdown` optimized for token-by-token rendering with built-in GFM support)

**Settings (`/settings`)**
- Profile section: name, background, interests (textarea), news style (select), language
- Topics section: add/remove interest tags
- Sources section: list of RSS feeds, add new, enable/disable, delete
- Search queries section: Tavily search queries for topic discovery
- LLM section: display current provider info (read-only, configured via ENV -- settings-driven override deferred to post-MVP P1)
- Save button, success/error feedback

**Routing**: TanStack Router with type-safe file-based routing. Three routes:
- `/` - Daily feed (home)
- `/article/$topicId` - Deep-dive article view (type-safe params)
- `/settings` - Preferences and source configuration

### Component Hierarchy

```
App
├── Login
└── AuthenticatedLayout
    ├── Header (title, nav, tag filter)
    ├── Feed
    │   ├── DaySection (per day)
    │   │   ├── DateHeader
    │   │   └── TopicCard[] (per topic)
    │   │       ├── Headline
    │   │       ├── Summary
    │   │       ├── TagBadge[]
    │   │       └── SourceCount
    │   └── InfiniteScrollTrigger
    ├── Article
    │   ├── ArticleHeader (headline, meta)
    │   ├── ArticleContent (markdown renderer)
    │   ├── RefreshButton
    │   └── SourceList
    └── Settings
        ├── ProfileForm
        ├── TopicsForm
        ├── SourcesManager
        └── SearchQueriesForm
```

### Key Libraries

**UI**: ShadCN/ui components with BasaltUI theme (`@basalt-ui` from [jkrumm/basalt-ui](https://github.com/jkrumm/basalt-ui)) for consistent ShadCN + Tailwind CSS styling. Install components via `bunx --bun shadcn@latest add <component>`.

---

## 5. Infrastructure

### Environment Variables

All config validated centrally with Zod at startup.

```bash
# Required
AUTH_SECRET=              # Shared secret for login
LLM_PROVIDER=google      # google | openai | anthropic | openai-compatible
LLM_MODEL=gemini-2.0-flash-001  # Default model for all operations
LLM_API_KEY=              # API key for the LLM provider
TAVILY_API_KEY=           # Tavily API key (free tier: 1000 credits/mo)

# Optional - LLM
LLM_BASE_URL=             # Custom base URL for LLM API
LLM_MODEL_FAST=           # Fast model for headlines/scoring (post-MVP P1, defaults to LLM_MODEL)
LLM_MODEL_PRO=            # Pro model for article generation (post-MVP P1, defaults to LLM_MODEL)

# Optional - Observability
SENTRY_DSN=               # Sentry DSN (optional, no-op if unset)

# Optional - Pipeline Adapters (see PIPELINE.md)
FIRECRAWL_URL=            # Self-hosted Firecrawl URL (post-MVP, e.g. http://localhost:3002)
EXA_API_KEY=              # Exa neural search (post-MVP)
GNEWS_API_KEY=            # GNews API (post-MVP, 100 req/day free)
SERPER_API_KEY=           # Serper Google SERP API (post-MVP)
PERPLEXITY_API_KEY=       # Perplexity AI research tool (post-MVP, Stage 3 only)

# Optional - General
NODE_ENV=production       # production | development (controls pino-pretty, defaults to development)
PORT=3000                 # Server port (default: 3000)
DATABASE_PATH=/app/data/open-news.db  # SQLite database path
TIMEZONE=UTC              # Timezone for cron scheduling
CRON_SCHEDULE=0 6 * * *   # Cron expression for daily digest (default: 6am)
LOG_LEVEL=info            # trace | debug | info | warn | error | fatal (default: debug in dev, info in prod)
```

### LLM Model Factory

```typescript
// apps/server/src/model.ts
function createModel() {
  const { LLM_PROVIDER, LLM_MODEL, LLM_API_KEY, LLM_BASE_URL } = process.env;
  switch (LLM_PROVIDER) {
    case 'google':
      return google(LLM_MODEL, { apiKey: LLM_API_KEY });
    case 'openai':
      return openai(LLM_MODEL, { apiKey: LLM_API_KEY, baseURL: LLM_BASE_URL });
    case 'anthropic':
      return anthropic(LLM_MODEL, { apiKey: LLM_API_KEY, baseURL: LLM_BASE_URL });
    case 'openai-compatible':
      return createOpenAICompatible({ apiKey: LLM_API_KEY, baseURL: LLM_BASE_URL })
        .chatModel(LLM_MODEL);
  }
}
```

### SQLite Configuration

```typescript
import { Database } from 'bun:sqlite';
const sqlite = new Database(process.env.DATABASE_PATH ?? './data/open-news.db');
sqlite.run('PRAGMA journal_mode = WAL');
sqlite.run('PRAGMA busy_timeout = 5000');
sqlite.run('PRAGMA synchronous = NORMAL');
sqlite.run('PRAGMA foreign_keys = ON');
```

### Logger Factory

```typescript
// packages/shared/src/logger.ts
import pino, { type Logger } from 'pino';

const isDev = process.env.NODE_ENV !== 'production';

export function createLogger(service: string): Logger {
  return pino({
    level: process.env.LOG_LEVEL ?? (isDev ? 'debug' : 'info'),
    timestamp: pino.stdTimeFunctions.isoTime,
    transport: isDev
      ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'HH:MM:ss.l', ignore: 'pid,hostname' } }
      : undefined,
  }).child({ service });
}
```

### Dockerfile

```dockerfile
# Stage 1: Install all dependencies
FROM oven/bun:1 AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/
COPY packages/shared/package.json ./packages/shared/
RUN bun install --frozen-lockfile

# Stage 2: Build React SPA
FROM deps AS build-web
WORKDIR /app
COPY packages/shared/ ./packages/shared/
COPY apps/web/ ./apps/web/
RUN bun run --cwd apps/web build

# Stage 3: Production runtime
FROM oven/bun:1-slim AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY packages/shared/package.json ./packages/shared/
RUN bun install --frozen-lockfile --production
COPY packages/shared/ ./packages/shared/
COPY apps/server/ ./apps/server/
COPY --from=build-web /app/apps/web/dist ./apps/web/dist
RUN mkdir -p /app/data && chown -R bun:bun /app/data
USER bun
ENV NODE_ENV=production
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1
CMD ["bun", "run", "apps/server/src/index.ts"]
```

### Docker Compose

```yaml
services:
  open-news:
    image: ghcr.io/jkrumm/open-news:latest
    container_name: open-news
    restart: unless-stopped
    ports:
      - '3000:3000'
    volumes:
      - open-news-data:/app/data
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - PORT=3000
      - DATABASE_PATH=/app/data/open-news.db

volumes:
  open-news-data:
```

---

## 6. Dependencies

### Server (`apps/server/package.json`)

```json
{
  "dependencies": {
    "@mastra/core": "latest",
    "@ai-sdk/google": "latest",
    "@ai-sdk/openai": "latest",
    "@ai-sdk/anthropic": "latest",
    "ai": "latest",
    "hono": "latest",
    "hono-pino": "latest",
    "pino": "latest",
    "drizzle-orm": "latest",
    "@extractus/feed-extractor": "latest",
    "@mozilla/readability": "latest",
    "linkedom": "latest",
    "fast-dice-coefficient": "latest",
    "croner": "latest",
    "zod": "latest",
    "@sentry/bun": "latest",
    "@open-news/shared": "workspace:*"
  },
  "devDependencies": {
    "drizzle-kit": "latest",
    "pino-pretty": "latest",
    "typescript": "latest"
  }
}
```

### Web (`apps/web/package.json`)

```json
{
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "@tanstack/react-router": "^1.114.0",
    "@ai-sdk/react": "latest",
    "@tanstack/react-query": "^5.0.0",
    "streamdown": "latest",
    "lucide-react": "latest",
    "@open-news/shared": "workspace:*",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "latest",
    "@tanstack/router-plugin": "^1.114.0",
    "@tanstack/react-router-devtools": "^1.114.0",
    "vite": "latest",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/vite": "latest",
    "typescript": "latest",
    "@types/react": "latest",
    "@types/react-dom": "latest"
  }
}
```
