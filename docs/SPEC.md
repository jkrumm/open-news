# OpenNews - Technical Specification

> Personal AI-powered news aggregator. Single Docker container. Provider-agnostic LLM.
> Self-hosted, open-source, privacy-first.

---

## 1. Product Overview

### Vision

OpenNews is a self-hosted, AI-powered news aggregator that delivers a personalized daily news feed. It scrapes configured sources (RSS feeds, Hacker News, Tavily web search), deduplicates and groups articles by topic, generates personalized headlines using an LLM, and offers on-demand deep-dive article generation from multiple sources.

### Core User Flows

**1. Configure preferences** (one-time setup)
- Describe personal background (role, expertise, interests)
- Set preferred news style (technical depth, tone, language)
- Add RSS feeds and topic interests
- Configure LLM provider and API key

**2. Browse daily feed** (daily usage)
- Open app, see today's personalized headlines
- Scroll down for previous days (infinite scroll)
- Each headline shows source count, tags, and a brief summary
- Filter by tags (AI, Tech, Finance, etc.)

**3. Deep-dive into a topic** (on-demand)
- Click a headline to open the article view
- Article is generated on-demand by the LLM from all grouped sources
- Streamed to the browser as it generates
- Cached for future visits, with a refresh button for updates
- Inline source references throughout the article

### Non-Goals (MVP)

- Multi-user support (single user, shared secret auth)
- YouTube transcript parsing
- Spotify/podcast integration
- Reddit API integration (use Reddit RSS instead)
- Mobile app (responsive web is sufficient)
- Real-time notifications / push

---

## 2. Architecture Decision Records

### ADR-001: AI Framework - Mastra as Library

**Decision**: Use `@mastra/core` as a library within a custom Hono server, not as a standalone Mastra server via `mastra build`.

**Context**: Mastra's `mastra build` command produces a Node.js Hono server. We need a Bun server that also serves a React SPA and custom REST endpoints. Using Mastra as a standalone server would require either two processes or complex routing.

**Approach**:
- Import `@mastra/core` and define agents, workflows, and tools programmatically
- Initialize the `Mastra` instance at server startup
- Invoke agents and workflows from custom Hono route handlers
- The Hono server is the single entry point serving everything

**Consequences**:
- Full control over the server, routing, and middleware
- No dependency on `mastra build` or the Mastra CLI
- Agents/workflows/tools are standard TypeScript - testable and debuggable
- We lose Mastra's built-in admin UI (not needed for single-user)

### ADR-002: LLM Provider Strategy - Provider-Agnostic via AI SDK

**Decision**: Use the Vercel AI SDK's provider system for LLM abstraction. User configures their preferred provider via environment variables.

**Context**: The user has access to Google Gemini, OpenAI (custom URL), Anthropic (custom URL). Other users of the open-source project will have different providers.

**Configuration** (environment variables):
```
LLM_PROVIDER=google|openai|anthropic|openai-compatible
LLM_MODEL=gemini-2.0-flash-001
LLM_API_KEY=...
LLM_BASE_URL=              # optional, for custom endpoints/proxies
```

**Packages**:
- `ai` - Core AI SDK
- `@ai-sdk/google` - Google Gemini
- `@ai-sdk/openai` - OpenAI + OpenAI-compatible
- `@ai-sdk/anthropic` - Anthropic

**Model resolution** at startup:
```typescript
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

### ADR-003: Data Sources - RSS + Tavily + Hacker News

**Decision**: MVP uses three source types: RSS feeds, Hacker News API, and Tavily web search. No dedicated news API subscription required.

**Rationale**:

| Source | Role | Cost | Why |
|--------|------|------|-----|
| RSS feeds | Follow specific publications | Free | User controls sources, reliable, real-time |
| Hacker News API | Tech community signal | Free | No auth, score = quality signal, unlimited |
| Tavily Search | Topic-based discovery | Free (1K credits/mo) | Finds articles RSS might miss |

**Why not dedicated News APIs?**
- NewsAPI.org: Free tier is localhost-only, $449/mo minimum for production
- TheNewsAPI: 3 requests/day on free tier - unusable
- GNews: 100 req/day free but non-commercial license
- Mediastack: 100 req/month free, no HTTPS

**RSS is the backbone**: Free, reliable, user-controlled. Combined with Tavily for discovery and HN for tech community picks, this covers the MVP without paid API subscriptions.

**Content extraction**: For articles where RSS only provides a snippet, use `@mozilla/readability` + `jsdom` to extract full text. Fall back to `tavily_extract` for JS-heavy sites.

### ADR-004: Database - SQLite via bun:sqlite + Drizzle ORM

**Decision**: Use Bun's built-in SQLite driver (`bun:sqlite`) with Drizzle ORM for type-safe queries and migrations.

**Rationale**:
- Single-file database - perfect for a single Docker container
- `bun:sqlite` is 3-6x faster than `better-sqlite3`, zero additional dependencies
- WAL mode enables concurrent reads during cron job writes
- Drizzle provides type-safe queries, migrations, and schema management
- No external database server needed

**Configuration**:
```typescript
import { Database } from 'bun:sqlite';
const sqlite = new Database(process.env.DATABASE_PATH ?? './data/open-news.db');
sqlite.run('PRAGMA journal_mode = WAL');
sqlite.run('PRAGMA busy_timeout = 5000');
sqlite.run('PRAGMA synchronous = NORMAL');
sqlite.run('PRAGMA foreign_keys = ON');
```

**Volume mount**: The `/app/data` directory is mounted as a Docker volume for persistence.

### ADR-005: Frontend - React SPA with Vite, served by Hono

**Decision**: Build the frontend as a React SPA using Vite. In production, serve the built static files from the Hono backend. In development, use Vite's dev server with a proxy to the backend.

**Rationale**:
- Vite provides HMR, React Fast Refresh, and a mature plugin ecosystem
- Bun runs Vite natively (no Node.js needed)
- Production: Hono serves `/assets/*` as static files and `/*` as SPA fallback
- Single port, single process in production

**Streaming**: Use `@ai-sdk/react`'s `useChat` hook for streaming LLM-generated articles. The Hono backend uses the AI SDK's `streamText` with `toUIMessageStreamResponse()`.

**Styling**: Tailwind CSS v4 (CSS-first config, no `tailwind.config.js`).

**Routing**: `react-router-dom` with three routes:
- `/` - Daily feed (home)
- `/article/:id` - Deep-dive article view
- `/settings` - Preferences and source configuration

### ADR-006: Cron Scheduling - croner

**Decision**: Use `croner` for in-process cron scheduling instead of Mastra's Inngest integration or external cron services.

**Rationale**:
- Inngest requires an external service (adds infrastructure complexity)
- `croner` is a modern, ESM-compatible cron library that works with Bun
- Runs in the same process - no external dependencies
- Supports timezone-aware scheduling

**Implementation**:
```typescript
import { Cron } from 'croner';

// Run daily at 06:00 in configured timezone
new Cron('0 6 * * *', { timezone: process.env.TIMEZONE ?? 'Europe/Berlin' }, async () => {
  await runDailyAggregation();
});
```

### ADR-007: Content Extraction - Readability + Tavily Fallback

**Decision**: Use `@mozilla/readability` with `jsdom` as the primary content extraction method. Fall back to Tavily Extract for URLs that fail.

**Rationale**:
- Readability is the industry standard (used in Firefox Reader View)
- Free and unlimited - no API costs
- Handles most static HTML news sites well
- Tavily Extract handles JS-rendered content and paywalled sites as a fallback

**Cost**: Tavily Extract costs 1 credit per 5 URLs. With 1,000 free credits/month, budget ~200 fallback extractions (1,000 URLs).

### ADR-008: Deduplication - URL Normalization + Title Similarity

**Decision**: Two-layer deduplication strategy without a vector database.

**Layer 1 - URL Normalization**:
- Strip tracking parameters (`utm_*`, `ref`, `source`, `fbclid`, etc.)
- Normalize `www.` prefix, trailing slashes, protocol
- Catches exact republishing and syndicated links

**Layer 2 - Title Similarity**:
- Use Dice's coefficient via `string-similarity` package
- Normalize titles: lowercase, remove punctuation
- Threshold: similarity > 0.7 = likely same story
- Compare against articles from the last 48 hours only

**Why not embeddings/SimHash?**
- For < 500 articles/day, O(n^2) title comparison takes < 100ms
- Adds complexity without proportional value at MVP scale
- Can be upgraded to SimHash/embeddings later if volume grows

---

## 3. System Architecture

### Monorepo Structure

```
open-news/
├── apps/
│   ├── server/                    # Hono backend + Mastra
│   │   ├── src/
│   │   │   ├── index.ts           # Server entry point
│   │   │   ├── config.ts          # Environment config + validation
│   │   │   ├── model.ts           # LLM model factory
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
│   │   │   │   ├── ingestion.ts   # Source fetching orchestrator
│   │   │   │   ├── rss.ts         # RSS feed parser
│   │   │   │   ├── hackernews.ts  # HN API client
│   │   │   │   ├── tavily.ts      # Tavily search client
│   │   │   │   ├── extractor.ts   # Content extraction
│   │   │   │   ├── dedup.ts       # Deduplication
│   │   │   │   └── cron.ts        # Cron job setup
│   │   │   └── mastra/
│   │   │       ├── index.ts       # Mastra instance
│   │   │       ├── agents/
│   │   │       │   ├── headline-agent.ts    # Groups + generates headlines
│   │   │       │   └── article-agent.ts     # Generates deep-dive articles
│   │   │       ├── workflows/
│   │   │       │   └── daily-digest.ts      # Daily aggregation workflow
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
│   └── shared/                    # Shared types
│       ├── src/
│       │   ├── index.ts
│       │   └── types.ts           # API types, domain models
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
    └── SPEC.md                    # This file
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
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────┐  │   │    │
│  │  │  │  Headline   │  │  Article   │  │ Tools  │  │   │    │
│  │  │  │  Agent      │  │  Agent     │  │        │  │   │    │
│  │  │  └────────────┘  └────────────┘  └────────┘  │   │    │
│  │  │  ┌────────────────────────────────────────┐   │   │    │
│  │  │  │  Daily Digest Workflow                  │   │   │    │
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

### Data Flow: Daily Aggregation

```
06:00 Cron Trigger
       │
       v
┌──────────────────────────────────────────────────┐
│  1. FETCH (parallel)                              │
│  ├── RSS feeds (rss-parser, all configured feeds) │
│  ├── Hacker News API (top 50 stories)             │
│  └── Tavily Search (per configured topic)         │
└──────────────────┬───────────────────────────────┘
                   │ raw articles
                   v
┌──────────────────────────────────────────────────┐
│  2. DEDUPLICATE                                   │
│  ├── URL normalization (strip tracking params)    │
│  ├── Title similarity (Dice coefficient > 0.7)    │
│  └── Filter already-seen articles (last 48h)      │
└──────────────────┬───────────────────────────────┘
                   │ unique articles
                   v
┌──────────────────────────────────────────────────┐
│  3. EXTRACT CONTENT (parallel, for snippets-only) │
│  ├── @mozilla/readability (primary)               │
│  └── tavily_extract (fallback for failures)       │
└──────────────────┬───────────────────────────────┘
                   │ articles with content
                   v
┌──────────────────────────────────────────────────┐
│  4. STORE raw articles in SQLite                  │
└──────────────────┬───────────────────────────────┘
                   │
                   v
┌──────────────────────────────────────────────────┐
│  5. LLM: GROUP + HEADLINE (Mastra Headline Agent) │
│  ├── Receives all new articles + user preferences │
│  ├── Groups articles by topic/story               │
│  ├── Assigns relevance score per user interests   │
│  ├── Generates personalized headline + summary    │
│  └── Assigns tags                                 │
└──────────────────┬───────────────────────────────┘
                   │ daily topics with headlines
                   v
┌──────────────────────────────────────────────────┐
│  6. STORE daily_topics + links to raw_articles    │
└──────────────────────────────────────────────────┘
```

### Data Flow: Article Deep-Dive (On-Demand)

```
User clicks headline
       │
       v
┌──────────────────────────────────────────┐
│  Check cache (generated_articles table)   │
│  ├── Hit: return cached markdown          │
│  └── Miss: continue to generation         │
└──────────────────┬───────────────────────┘
                   │
                   v
┌──────────────────────────────────────────────────┐
│  Mastra Article Agent (streaming)                 │
│  ├── Receives: topic headline, grouped source     │
│  │   articles, user preferences                   │
│  ├── Tools available:                             │
│  │   ├── tavily_search (find more on this topic)  │
│  │   ├── tavily_extract (get full article text)   │
│  │   └── fetch_content (readability extraction)   │
│  ├── Generates comprehensive article in markdown  │
│  ├── Includes inline source references            │
│  └── Streams tokens to client via SSE             │
└──────────────────┬───────────────────────────────┘
                   │
                   v
┌──────────────────────────────────────────┐
│  Cache generated article in SQLite        │
└──────────────────────────────────────────┘
```

---

## 4. Data Model

### SQLite Schema (Drizzle)

```typescript
// packages/shared/src/types.ts - Source types enum
export const SOURCE_TYPES = ['rss', 'hackernews', 'tavily'] as const;
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
  content: text('content'),                    // extracted full text (nullable)
  snippet: text('snippet'),                    // short excerpt
  author: text('author'),
  score: integer('score'),                     // HN score, null for RSS
  publishedAt: text('published_at'),
  scrapedAt: text('scraped_at').notNull().$defaultFn(() => new Date().toISOString()),
  scrapedDate: text('scraped_date').notNull(), // YYYY-MM-DD for daily grouping
});

// ─── Daily Topics (AI-grouped headlines) ──────────────────
export const dailyTopics = sqliteTable('daily_topics', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  date: text('date').notNull(),                // YYYY-MM-DD
  headline: text('headline').notNull(),        // AI-generated headline
  summary: text('summary').notNull(),          // AI-generated summary (2-3 sentences)
  relevanceScore: real('relevance_score').notNull().default(0), // 0-1, for sorting
  sourceCount: integer('source_count').notNull().default(1),
  createdAt: text('created_at').notNull().$defaultFn(() => new Date().toISOString()),
});

// ─── Tags ─────────────────────────────────────────────────
export const tags = sqliteTable('tags', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull().unique(),       // e.g. 'ai', 'typescript', 'finance'
  color: text('color'),                        // optional hex color
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
  content: text('content').notNull(),          // markdown
  generatedAt: text('generated_at').notNull().$defaultFn(() => new Date().toISOString()),
});
```

### Indexes

```typescript
// Add these indexes for query performance
export const rawArticlesDateIdx = index('raw_articles_date_idx').on(rawArticles.scrapedDate);
export const rawArticlesUrlIdx = uniqueIndex('raw_articles_url_idx').on(rawArticles.urlNormalized);
export const dailyTopicsDateIdx = index('daily_topics_date_idx').on(dailyTopics.date);
export const topicTagsTopicIdx = index('topic_tags_topic_idx').on(topicTags.topicId);
export const topicSourcesTopicIdx = index('topic_sources_topic_idx').on(topicSources.topicId);
```

---

## 5. API Design

### Authentication

Simple shared-secret authentication:

```
AUTH_SECRET=your-secret-here  # environment variable
```

**Login flow**:
1. POST `/api/v1/auth/login` with `{ secret: "..." }`
2. Server validates against `AUTH_SECRET`
3. Returns HTTP-only secure cookie with session token (signed JWT or random token)
4. All `/api/v1/*` routes require valid session cookie
5. GET `/api/v1/auth/check` returns 200 if authenticated, 401 if not

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

# Feed (daily topics)
GET    /api/v1/feed                 → { days: DayWithTopics[] }
       ?cursor=2026-02-07           # pagination by date
       &limit=7                     # days to return
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

The article generation endpoint uses Server-Sent Events:

```typescript
// Server (apps/server/src/routes/article.ts)
import { streamSSE } from 'hono/streaming';

article.post('/:topicId/generate', async (c) => {
  const topicId = c.req.param('topicId');
  const topic = await getTopicWithSources(topicId);
  const settings = await getSettings();

  const agent = mastra.getAgent('articleGenerator');
  const result = await agent.stream({
    messages: [{ role: 'user', content: buildArticlePrompt(topic, settings) }],
  });

  // Stream using AI SDK's response format
  return result.toUIMessageStreamResponse();
});
```

```typescript
// Client (apps/web/src/routes/Article.tsx)
import { useChat } from '@ai-sdk/react';

function ArticlePage({ topicId }: { topicId: string }) {
  const { messages, isLoading, reload } = useChat({
    api: `/api/v1/article/${topicId}/generate`,
    initialInput: 'generate',
  });

  // Or use a simpler custom approach with fetch + ReadableStream
  // for non-conversational streaming (see implementation notes)
}
```

---

## 6. Mastra Configuration

### Mastra Instance

```typescript
// apps/server/src/mastra/index.ts
import { Mastra } from '@mastra/core';
import { headlineAgent } from './agents/headline-agent';
import { articleAgent } from './agents/article-agent';
import { dailyDigestWorkflow } from './workflows/daily-digest';
import { tavilySearchTool, tavilyExtractTool, fetchContentTool } from './tools';

export const mastra = new Mastra({
  agents: {
    headlineGenerator: headlineAgent,
    articleGenerator: articleAgent,
  },
  workflows: {
    dailyDigest: dailyDigestWorkflow,
  },
  tools: {
    tavilySearch: tavilySearchTool,
    tavilyExtract: tavilyExtractTool,
    fetchContent: fetchContentTool,
  },
});
```

### Headline Agent

Purpose: Receives the day's scraped articles + user preferences. Groups articles by topic/story, assigns relevance scores, generates personalized headlines and summaries, assigns tags.

```typescript
// apps/server/src/mastra/agents/headline-agent.ts
import { Agent } from '@mastra/core/agent';
import { createModel } from '../../model';

export const headlineAgent = new Agent({
  id: 'headlineGenerator',
  model: createModel(),
  instructions: `You are a news curator. Given a list of articles scraped today and the user's
profile (background, interests, preferred style), you must:

1. GROUP articles that cover the same story/topic into clusters
2. RANK clusters by relevance to the user's interests (0.0 to 1.0)
3. GENERATE a personalized headline and 2-3 sentence summary for each cluster
4. ASSIGN tags from the existing tag list (or suggest new ones)
5. DISCARD clusters that score below 0.3 relevance

Return a structured JSON response following the provided schema.
Prioritize recency, significance, and personal relevance.
Write headlines in the user's preferred style and language.`,
});
```

**Input**: Structured JSON with articles list + user preferences
**Output**: Structured JSON with grouped topics, headlines, summaries, scores, tags

### Article Agent

Purpose: Generates a comprehensive deep-dive article from multiple sources on a single topic. Has access to tools for fetching additional information.

```typescript
// apps/server/src/mastra/agents/article-agent.ts
import { Agent } from '@mastra/core/agent';
import { createModel } from '../../model';
import { tavilySearchTool, tavilyExtractTool, fetchContentTool } from '../tools';

export const articleAgent = new Agent({
  id: 'articleGenerator',
  model: createModel(),
  tools: {
    tavilySearch: tavilySearchTool,
    tavilyExtract: tavilyExtractTool,
    fetchContent: fetchContentTool,
  },
  instructions: `You are a skilled journalist writing a personalized news article.

Given a topic headline, summary, and source articles, write a comprehensive article that:

1. SYNTHESIZES information from all provided sources
2. RESEARCHES additional context using your tools if needed
3. WRITES in the user's preferred style and language
4. INCLUDES inline source references as markdown links
5. STRUCTURES the article with clear sections (## headings)
6. PROVIDES analysis and context, not just facts
7. ADAPTS technical depth to the user's background

Format: Markdown. Length: 800-2000 words depending on topic complexity.
Always cite sources inline: [Source Name](url).`,
});
```

### Daily Digest Workflow

```typescript
// apps/server/src/mastra/workflows/daily-digest.ts
import { Workflow, Step } from '@mastra/core/workflows';

export const dailyDigestWorkflow = new Workflow({
  id: 'dailyDigest',
  steps: {
    fetchSources: new Step({
      id: 'fetchSources',
      execute: async ({ context }) => {
        // Parallel fetch from all sources
        // Returns: { articles: RawArticle[] }
      },
    }),
    deduplicate: new Step({
      id: 'deduplicate',
      execute: async ({ context }) => {
        // URL normalization + title similarity
        // Returns: { uniqueArticles: RawArticle[] }
      },
    }),
    extractContent: new Step({
      id: 'extractContent',
      execute: async ({ context }) => {
        // Extract full text for snippet-only articles
        // Returns: { enrichedArticles: RawArticle[] }
      },
    }),
    storeArticles: new Step({
      id: 'storeArticles',
      execute: async ({ context }) => {
        // Persist to SQLite
      },
    }),
    generateHeadlines: new Step({
      id: 'generateHeadlines',
      execute: async ({ context }) => {
        // Invoke headlineAgent with articles + settings
        // Returns: { topics: DailyTopic[] }
      },
    }),
    storeTopics: new Step({
      id: 'storeTopics',
      execute: async ({ context }) => {
        // Persist topics, tags, and source links to SQLite
      },
    }),
  },
});
```

### Tools

```typescript
// apps/server/src/mastra/tools/tavily-search.ts
import { createTool } from '@mastra/core/tools';
import { z } from 'zod';

export const tavilySearchTool = createTool({
  id: 'tavilySearch',
  description: 'Search the web for recent articles on a specific topic',
  inputSchema: z.object({
    query: z.string().describe('Search query'),
    timeRange: z.enum(['day', 'week', 'month']).default('day'),
    maxResults: z.number().default(5),
  }),
  execute: async ({ context }) => {
    const response = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.TAVILY_API_KEY}`,
      },
      body: JSON.stringify({
        query: context.query,
        search_depth: 'basic',
        time_range: context.timeRange,
        max_results: context.maxResults,
        include_raw_content: true,
      }),
    });
    return response.json();
  },
});
```

---

## 7. Frontend Design

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
- Click card → navigate to `/article/:topicId`
- Tag filter bar: clickable tag pills, toggleable, filters feed

**Article (`/article/:topicId`)**
- Back button to feed
- Topic headline + metadata (date, source count, tags)
- If cached: render markdown immediately
- If not cached: show loading state, POST to generate, stream markdown in real-time
- Refresh button: invalidates cache, regenerates
- Source list at the bottom (all grouped raw articles with links)
- Rendered markdown with `react-markdown` + `remark-gfm`

**Settings (`/settings`)**
- Profile section: name, background, interests (textarea), news style (select), language
- Topics section: add/remove interest tags
- Sources section: list of RSS feeds, add new, enable/disable, delete
- Search queries section: Tavily search queries for topic discovery
- LLM section: display current provider info (read-only, configured via ENV)
- Save button, success/error feedback

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

```json
{
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "react-router-dom": "^7.0.0",
    "@ai-sdk/react": "^1.0.0",
    "@tanstack/react-query": "^5.0.0",
    "react-markdown": "^9.0.0",
    "remark-gfm": "^4.0.0",
    "lucide-react": "latest",
    "tailwindcss": "^4.0.0"
  }
}
```

---

## 8. Infrastructure

### Environment Variables

```bash
# Required
AUTH_SECRET=              # Shared secret for login
LLM_PROVIDER=google      # google | openai | anthropic | openai-compatible
LLM_MODEL=gemini-2.0-flash-001
LLM_API_KEY=              # API key for the LLM provider
TAVILY_API_KEY=           # Tavily API key (free tier: 1000 credits/mo)

# Optional
LLM_BASE_URL=             # Custom base URL for LLM API
PORT=3000                 # Server port (default: 3000)
DATABASE_PATH=/app/data/open-news.db  # SQLite database path
TIMEZONE=Europe/Berlin    # Timezone for cron scheduling
CRON_SCHEDULE=0 6 * * *   # Cron expression for daily digest (default: 6am)
LOG_LEVEL=info            # debug | info | warn | error
```

### Dockerfile

```dockerfile
# ============================================
# Stage 1: Install all dependencies
# ============================================
FROM oven/bun:1 AS deps

WORKDIR /app

COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/
COPY packages/shared/package.json ./packages/shared/

RUN bun install --frozen-lockfile

# ============================================
# Stage 2: Build React SPA
# ============================================
FROM deps AS build-web

WORKDIR /app

COPY packages/shared/ ./packages/shared/
COPY apps/web/ ./apps/web/

RUN bun run --cwd apps/web build

# ============================================
# Stage 3: Production runtime
# ============================================
FROM oven/bun:1-slim AS runtime

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Copy workspace config + install production deps
COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY packages/shared/package.json ./packages/shared/

RUN bun install --frozen-lockfile --production

# Copy source code (Bun runs TS directly)
COPY packages/shared/ ./packages/shared/
COPY apps/server/ ./apps/server/

# Copy built frontend
COPY --from=build-web /app/apps/web/dist ./apps/web/dist

# Create data directory
RUN mkdir -p /app/data && chown -R bun:bun /app/data

USER bun

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["bun", "run", "apps/server/src/index.ts"]
```

### Docker Compose

```yaml
# docker-compose.yml
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

**User setup**:
```bash
# 1. Create .env file
cat > .env << 'EOF'
AUTH_SECRET=your-secret-password
LLM_PROVIDER=google
LLM_MODEL=gemini-2.0-flash-001
LLM_API_KEY=your-google-api-key
TAVILY_API_KEY=your-tavily-api-key
TIMEZONE=Europe/Berlin
EOF

# 2. Start
docker compose up -d

# 3. Open
open http://localhost:3000
```

### GitHub Actions CI/CD

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  check:
    name: Lint & Typecheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest
      - run: bun install --frozen-lockfile
      - run: bun run check        # biome check
      - run: bun run typecheck     # tsc -b

  docker:
    name: Build & Push Docker Image
    needs: check
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3
      - uses: docker/setup-qemu-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha
            type=raw,value=latest

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Root package.json Scripts

```json
{
  "scripts": {
    "dev": "bun run --filter '*' dev",
    "dev:server": "bun run --cwd apps/server dev",
    "dev:web": "bun run --cwd apps/web dev",
    "build": "bun run build:web",
    "build:web": "bun run --cwd apps/web build",
    "check": "biome check .",
    "check:fix": "biome check --write .",
    "format": "biome format --write .",
    "lint": "biome lint .",
    "typecheck": "tsc -b",
    "db:generate": "bun run --cwd apps/server drizzle-kit generate",
    "db:migrate": "bun run --cwd apps/server drizzle-kit migrate",
    "db:studio": "bun run --cwd apps/server drizzle-kit studio"
  }
}
```

### Biome Configuration

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "noUnusedImports": "error"
      }
    }
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "semicolons": "always",
      "trailingCommas": "all"
    }
  }
}
```

---

## 9. Dependencies

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
    "drizzle-orm": "latest",
    "rss-parser": "latest",
    "@mozilla/readability": "latest",
    "jsdom": "latest",
    "string-similarity": "latest",
    "croner": "latest",
    "zod": "latest",
    "@open-news/shared": "workspace:*"
  },
  "devDependencies": {
    "drizzle-kit": "latest",
    "@types/jsdom": "latest",
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
    "react-router-dom": "^7.0.0",
    "@ai-sdk/react": "latest",
    "@tanstack/react-query": "^5.0.0",
    "react-markdown": "latest",
    "remark-gfm": "latest",
    "lucide-react": "latest",
    "@open-news/shared": "workspace:*"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "latest",
    "vite": "latest",
    "tailwindcss": "^4.0.0",
    "@tailwindcss/vite": "latest",
    "typescript": "latest",
    "@types/react": "latest",
    "@types/react-dom": "latest"
  }
}
```

---

## 10. MVP Scope & Implementation Plan

### Phase 1: Project Setup

- [ ] Initialize Bun monorepo with workspaces
- [ ] Set up `packages/shared` with types
- [ ] Set up `apps/server` with Hono + basic health endpoint
- [ ] Set up `apps/web` with Vite + React + Tailwind
- [ ] Configure Biome (root config)
- [ ] Configure TypeScript (project references)
- [ ] Set up Drizzle ORM + SQLite schema + migrations
- [ ] Dockerfile + docker-compose.yml
- [ ] GitHub Actions CI (lint + typecheck + docker build)

### Phase 2: Backend Core

- [ ] Environment config validation (Zod)
- [ ] Auth middleware (shared secret + session cookie)
- [ ] Settings CRUD endpoints
- [ ] Sources CRUD endpoints
- [ ] LLM model factory (provider-agnostic)
- [ ] RSS feed parser service
- [ ] Hacker News API client
- [ ] Tavily search client
- [ ] Content extraction service (readability + Tavily fallback)
- [ ] Deduplication service (URL normalization + title similarity)
- [ ] Cron scheduling with croner

### Phase 3: AI Pipeline

- [ ] Mastra instance setup
- [ ] Mastra tools (Tavily search, extract, content fetch)
- [ ] Headline Agent (group + score + generate headlines)
- [ ] Daily Digest Workflow (fetch → dedup → extract → headline)
- [ ] Article Agent (deep-dive generation)
- [ ] Article generation endpoint with SSE streaming
- [ ] Article caching + refresh

### Phase 4: Frontend

- [ ] Login page
- [ ] Auth state management
- [ ] Settings page (profile, sources, topics)
- [ ] Feed page (daily topics, infinite scroll, tag filter)
- [ ] Article page (streaming markdown render)
- [ ] Responsive design (mobile-friendly)

### Phase 5: Polish

- [ ] Error handling (global error boundaries, API error responses)
- [ ] Loading states and skeletons
- [ ] Manual digest trigger (admin endpoint)
- [ ] Status page (last digest time, article count)
- [ ] Seed data / onboarding flow (default RSS feeds)

---

## 11. Default RSS Feeds (Starter Pack)

Pre-configured feeds for first-time setup (user can modify):

```json
[
  { "name": "Hacker News", "url": "https://hnrss.org/frontpage", "type": "rss" },
  { "name": "Lobsters", "url": "https://lobste.rs/rss", "type": "rss" },
  { "name": "TechCrunch", "url": "https://techcrunch.com/feed/", "type": "rss" },
  { "name": "The Verge", "url": "https://www.theverge.com/rss/index.xml", "type": "rss" },
  { "name": "Ars Technica", "url": "https://feeds.arstechnica.com/arstechnica/index", "type": "rss" },
  { "name": "Wired", "url": "https://www.wired.com/feed/rss", "type": "rss" },
  { "name": "The Guardian Tech", "url": "https://www.theguardian.com/technology/rss", "type": "rss" },
  { "name": "BBC Tech", "url": "http://feeds.bbci.co.uk/news/technology/rss.xml", "type": "rss" }
]
```

---

## 12. Cost Analysis

### Monthly Operating Cost (MVP)

| Resource | Cost | Notes |
|----------|------|-------|
| RSS feeds | $0 | Unlimited, free |
| Hacker News API | $0 | Unlimited, no auth |
| Tavily (free tier) | $0 | 1,000 credits/month |
| LLM (Gemini Flash) | ~$1-5 | Daily headlines + ~30 article deep-dives |
| VPS (Hetzner CX22) | ~$4/mo | 2 vCPU, 4GB RAM, 40GB SSD |
| **Total** | **~$5-10/mo** | |

### Tavily Credit Budget (1,000/month)

- Daily topic search: 3 queries x 30 days = 90 credits
- Content extraction fallback: ~100 URLs/month = 20 credits
- Article deep-dive research: ~30 articles x 2 searches = 60 credits
- **Total**: ~170 credits/month (well within free tier)

### LLM Token Estimate (Daily)

- Headline generation: ~5K input + ~2K output tokens
- Article generation (per article): ~10K input + ~3K output tokens
- Daily total: ~5K + (30 articles/month / 30 days) x 13K = ~18K tokens/day
- Monthly: ~540K tokens
- Gemini Flash cost: ~$0.04/day = ~$1.20/month
