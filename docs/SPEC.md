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
- Article ImageGen
- Proper Syntax rendering in articles
- GenAI for Articles
- GenAI diagrams for articles

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

**Challenged: Hono vs Elysia** (Feb 2026)

Hono wins decisively for this project:
1. **Mastra compatibility**: Mastra has an official Hono adapter (`MastraServer`). No Elysia adapter exists or is planned. Using Elysia would require building a custom adapter.
2. **SSE reliability**: Hono's built-in `streamSSE` is battle-tested. Elysia had a critical SSE performance bug (10x slower, issue #1369) -- fixed in v1.3.21 but still showing edge-case issues.
3. **Ecosystem**: Hono has 9.3M weekly npm downloads, cross-runtime support (Bun/Node/Deno/CF Workers), 40+ built-in middleware. Elysia is Bun-only with 323K downloads.
4. **SSR/SSG path**: HonoX meta-framework + `@hono/react-renderer` for future SSR needs. Elysia has nothing comparable.
5. **Performance**: Elysia is ~1.5x faster in synthetic benchmarks (397K vs 253K req/s), but this is irrelevant -- the bottleneck is LLM API latency, not HTTP routing.

### ADR-002: LLM Provider Strategy - Provider-Agnostic via AI SDK

**Decision**: Use the Vercel AI SDK's provider system for LLM abstraction. User configures their preferred provider via environment variables.

**Challenged: TanStack AI vs Vercel AI SDK** (Feb 2026)

TanStack AI (`@tanstack/ai` v0.3.1) is explicitly alpha with acknowledged bugs and breaking changes. Vercel AI SDK is at v6.x, production-proven. Both work identically with Hono (standard `Response` objects). The `useChat` APIs are nearly identical -- migration to TanStack AI later is cheap if it reaches v1.0. Sticking with Vercel AI SDK for stability.

**Model Tiers**: Support two model tiers via environment variables. The headline agent uses the fast model (cheaper, for grouping/scoring). The article agent uses the pro model (higher quality, for deep-dive generation). Both default to `LLM_MODEL` if not explicitly configured.

**Context**: The user has access to Google Gemini (custom URL), OpenAI (custom URL), Anthropic (custom URL). Other users of the open-source project will have different providers.

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

**Configuration source of truth (MVP)**: ENV vars are the sole config source for LLM provider/model/key. Settings UI for LLM config is deferred to post-MVP (see P1 roadmap). User preferences (profile, interests, news style, sources) live in the `settings` table. All config validated with Zod at startup.

### ADR-003: Data Sources - RSS + Tavily + Hacker News

**Decision**: MVP uses three source types: RSS feeds, Hacker News API, and Tavily web search. No dedicated news API subscription required.

**Rationale**:

| Source          | Role                         | Cost                 | Why                                        |
|-----------------|------------------------------|----------------------|--------------------------------------------|
| RSS feeds       | Follow specific publications | Free                 | User controls sources, reliable, real-time |
| Hacker News API | Tech community signal        | Free                 | No auth, score = quality signal, unlimited |
| Tavily Search   | Topic-based discovery        | Free (1K credits/mo) | Finds articles RSS might miss              |

**Why not dedicated News APIs?**
- NewsAPI.org: Free tier is localhost-only, $449/mo minimum for production
- TheNewsAPI: 3 requests/day on free tier - unusable
- GNews: 100 req/day free but non-commercial license
- Mediastack: 100 req/month free, no HTTPS

**Post-MVP: Additional sources** (Exa, GNews, Serper, etc.) can be added later as optional source adapters via the `SourceAdapter` interface. See [`docs/PIPELINE.md`](./PIPELINE.md) for adapter interfaces, registry, and extension guide.

**RSS is the backbone**: Free, reliable, user-controlled. Combined with Tavily for discovery and HN for tech community picks, this covers the MVP without paid API subscriptions.

**RSS parsing**: Use `@extractus/feed-extractor` instead of `rss-parser`. It has official Bun support, ESM-first design, supports RSS/Atom/RDF/JSON feeds, and is actively maintained (last release Oct 2025). `rss-parser` has not been released in 2+ years and is CJS-only.

**Content extraction**: See ADR-007 and [`docs/PIPELINE.md`](./PIPELINE.md) for the extraction chain architecture.

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

**SSR/SSG**: Post-MVP consideration. CSR with TanStack Query caching is sufficient for MVP -- the feed updates once/day, so client-side caching is effective. Hono has SSR capabilities (`@hono/react-renderer`, HonoX) if needed later without a metaframework. Infinite scroll over days is a client-side concern (pagination API + `useInfiniteQuery`): show 3 days by default, load more on scroll.

**Streaming**: Use `@ai-sdk/react`'s `useCompletion` hook for streaming LLM-generated articles (one-shot, not conversational). The Hono backend uses Mastra's `agent.stream()` with `toDataStreamResponse()`.

**Styling**: Tailwind CSS v4 (CSS-first config, no `tailwind.config.js`).

**Challenged: TanStack Router vs react-router-dom** (Feb 2026)

TanStack Router wins for this project:
1. **Type Safety**: Automatic type inference for route params, search params, and loader data. `navigate({ to: '/article/$topicId', params: { topicId: '123' } })` is fully typed and autocompleted.
2. **Search Param Validation**: Built-in Zod schema validation for URL search params (`validateSearch`), crucial for feed filtering and pagination.
3. **File-Based Routing**: Vite plugin (`@tanstack/router-plugin`) auto-generates routes from file structure with code splitting.
4. **Modern DX**: Built for React 19, devtools, and better integration with TanStack Query.
5. **Migration Cost**: Low - similar API surface to react-router-dom v7, but with superior type safety.

react-router-dom v7 added type safety, but it's opt-in and requires manual type definitions. TanStack Router infers types automatically from route definitions.

**Routing**: TanStack Router with type-safe file-based routing. Three routes:
- `/` - Daily feed (home)
- `/article/$topicId` - Deep-dive article view (type-safe params)
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

**Decision**: Use `@mozilla/readability` with `linkedom` as the primary content extraction method. Fall back to Tavily Extract for URLs that fail.

**Rationale**:
- Readability is the industry standard (used in Firefox Reader View)
- `linkedom` is 90% smaller than `jsdom` (~235KB vs ~20MB), 3x faster, 3x less heap usage
- `linkedom` is proven compatible with Readability in production (used by readability-js Rust crate)
- Free and unlimited - no API costs
- Handles most static HTML news sites well
- Tavily Extract handles JS-rendered content and paywalled sites as a fallback

**Cost**: Tavily Extract costs 1 credit per 5 URLs. With 1,000 free credits/month, budget ~200 fallback extractions (1,000 URLs).

**Pluggable Extractor Architecture**: `ContentExtractor` interface with a config-driven fallback chain. Each extractor implements `extract(url) → ExtractedContent | null`. Chain tries extractors in order: free/fast first, paid API last. See [`docs/PIPELINE.md`](./PIPELINE.md) for full adapter interfaces, chain behavior, and registry implementation.

**MVP**: ReadabilityExtractor (primary, free) + TavilyExtractor (fallback, paid). If all extractors fail, the article is discarded.

**Post-MVP**: Add FirecrawlExtractor (`@mendable/firecrawl-js` SDK) for self-hosted instances. Skip Crawl4AI -- Python-first, no official JS SDK.

### ADR-008: Deduplication - URL Normalization + Title Similarity

**Decision**: Two-layer deduplication strategy without a vector database.

**Layer 1 - URL Normalization**:
- Strip tracking parameters (`utm_*`, `ref`, `source`, `fbclid`, etc.)
- Normalize `www.` prefix, trailing slashes, protocol
- Catches exact republishing and syndicated links

**Layer 2 - Title Similarity**:
- Use Dice's coefficient via `fast-dice-coefficient` package (the `string-similarity` package is abandoned since 2021)
- Normalize titles: lowercase, remove punctuation
- Threshold: similarity > 0.7 = likely same story
- Compare against articles from the last 48 hours only

**Why not embeddings/SimHash?**
- For < 500 articles/day, O(n^2) title comparison takes < 100ms
- Adds complexity without proportional value at MVP scale
- Can be upgraded to SimHash/embeddings later if volume grows

**Challenged: AI-based deduplication** -- URL normalization + Dice coefficient is instant and free. For 100 articles, pairwise comparison takes <100ms. AI dedup would require ~4,950 LLM calls (n*(n-1)/2) per day, adding 8+ minutes of latency and cost. **Post-MVP**: Use a focused AI call only for borderline pairs (similarity 0.5-0.7) as a second pass -- maybe 5-10 targeted calls/day.

### ADR-009: Structured Logging - Pino + hono-pino + Logdy

**Decision**: Use Pino as the single structured logging layer across the entire application. Shared logger factory in `packages/shared`, request-scoped logging via `hono-pino` middleware, Sentry bridge via official `pinoIntegration`.

**Architecture**:

| Layer | Tool | Purpose |
|-------|------|---------|
| Logger factory | `packages/shared/src/logger.ts` | Shared Pino config, `createLogger(service)` |
| HTTP request logging | `hono-pino` middleware | requestId (UUID), responseTime, method, path, status |
| Error bridge | `Sentry.pinoIntegration()` | Forward `error`/`fatal` Pino logs to Sentry |
| Local dev viewing | `pino-pretty` (terminal) + Logdy (browser UI) | Human-readable exploration |
| Production | Raw NDJSON to stdout | Docker captures via logging driver |

**Shared logger factory** (`packages/shared/src/logger.ts`):
```typescript
import pino, { type Logger, type LoggerOptions } from 'pino';

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

export type { Logger } from 'pino';
```

**Hono integration** (server entry point):
```typescript
import { pinoLogger } from 'hono-pino';

app.use(pinoLogger({
  pino: pino({ /* shared config */ }),
  http: { reqId: () => crypto.randomUUID(), responseTime: true },
}));

// In route handlers: c.var.logger.info('Fetching articles');
```

**Sentry bridge** (server startup, before logger init):
```typescript
import * as Sentry from '@sentry/bun';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    integrations: [Sentry.pinoIntegration({ error: { levels: ['error', 'fatal'] } })],
  });
}
```

**Local dev scripts**:
```bash
bun run dev              # pino-pretty colored output in terminal
bun run dev | logdy      # pipe to Logdy browser UI (localhost:8080)
```

**Why Pino**: JSON structured logging is the standard for Docker/cloud. Pino is the fastest Node/Bun logger, outputs NDJSON to stdout (what Docker expects), and has first-class Hono and Sentry integrations. `console.log` is unstructured and not queryable.

**Why Logdy**: Standalone binary (`brew install logdy`), reads from stdin — no Pino transport needed. Provides a browser UI with auto-generated columns from JSON fields, faceted filtering, search. Complementary to `pino-pretty` (terminal vs browser).

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
    ├── SPEC.md                    # This file
    ├── PIPELINE.md                # Pipeline architecture + adapter interfaces
    └── IMPLEMENTATION.md          # Task breakdown
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
│  ├── RSS feeds (feed-extractor, all configured)   │
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
3. Returns HTTP-only secure cookie with a JWT (signed with key derived from `AUTH_SECRET`, no expiry)
4. All `/api/v1/*` routes require valid auth
5. GET `/api/v1/auth/check` returns 200 if authenticated, 401 if not

**JWT signing key**: Derived deterministically from `AUTH_SECRET` (e.g. HMAC-SHA256 with a static salt). This ensures JWTs survive server restarts without storing state. No token expiry — single-user app, session lives forever.

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

The article generation endpoint uses Server-Sent Events. Article generation is one-shot (not conversational), so we use `agent.stream()` with `toDataStreamResponse()` on the server and `useCompletion` on the client (not `useChat`, which is for multi-turn conversation).

```typescript
// Server (apps/server/src/routes/article.ts)
article.post('/:topicId/generate', async (c) => {
  const topicId = c.req.param('topicId');
  const topic = await getTopicWithSources(topicId);
  const settings = await getSettings();

  const agent = mastra.getAgent('articleGenerator');
  const stream = await agent.stream(buildArticlePrompt(topic, settings));

  // toDataStreamResponse() converts Mastra stream to AI SDK-compatible Response
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

## 6. Mastra Configuration

### Mastra Instance

```typescript
// apps/server/src/mastra/index.ts
import { Mastra } from '@mastra/core/mastra';
import { headlineAgent } from './agents/headline-agent';
import { articleAgent } from './agents/article-agent';
import { dailyDigestWorkflow } from './workflows/daily-digest';

export const mastra = new Mastra({
  agents: {
    headlineGenerator: headlineAgent,
    articleGenerator: articleAgent,
  },
  workflows: {
    dailyDigest: dailyDigestWorkflow,
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
  name: 'Headline Generator',
  model: createModel('fast'), // Uses LLM_MODEL_FAST (cheaper, for grouping/scoring)
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
**Output**: Structured JSON via `agent.generate()` with `structuredOutput: { schema }` option
```typescript
const response = await headlineAgent.generate(buildHeadlinePrompt(articles, settings), {
  structuredOutput: { schema: headlineOutputSchema },
});
const topics = response.object; // typed from Zod schema
```

### Article Agent

Purpose: Generates a comprehensive deep-dive article from multiple sources on a single topic. Has access to tools for fetching additional information.

```typescript
// apps/server/src/mastra/agents/article-agent.ts
import { Agent } from '@mastra/core/agent';
import { createModel } from '../../model';
import { tavilySearchTool, tavilyExtractTool, fetchContentTool } from '../tools';

export const articleAgent = new Agent({
  id: 'articleGenerator',
  name: 'Article Generator',
  model: createModel('pro'), // Uses LLM_MODEL_PRO (higher quality, for deep-dive articles)
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

**Streaming**: `agent.stream(prompt)` returns a `MastraModelOutput` with `.textStream`, `.text`, and `.toDataStreamResponse()` for Hono routes.

### Daily Digest Workflow

Uses Mastra v1 workflow API with `createWorkflow`/`createStep` and typed input/output schemas chained via `.then()`.

```typescript
// apps/server/src/mastra/workflows/daily-digest.ts
import { createWorkflow, createStep } from '@mastra/core/workflows';
import { z } from 'zod';

const rawArticleSchema = z.object({ title: z.string(), url: z.string(), /* ... */ });

const fetchSources = createStep({
  id: 'fetch-sources',
  inputSchema: z.object({ date: z.string() }),
  outputSchema: z.object({ articles: z.array(rawArticleSchema) }),
  execute: async ({ inputData }) => {
    // Parallel fetch from all sources (RSS, HN, Tavily)
    return { articles: [...] };
  },
});

const deduplicate = createStep({
  id: 'deduplicate',
  inputSchema: z.object({ articles: z.array(rawArticleSchema) }),
  outputSchema: z.object({ articles: z.array(rawArticleSchema) }),
  execute: async ({ inputData }) => {
    // URL normalization + title similarity (Dice coefficient)
    return { articles: uniqueArticles };
  },
});

// ... extractContent, storeArticles, generateHeadlines, storeTopics steps ...

export const dailyDigestWorkflow = createWorkflow({
  id: 'daily-digest',
  inputSchema: z.object({ date: z.string() }),
  outputSchema: z.object({ topicCount: z.number() }),
})
  .then(fetchSources)
  .then(deduplicate)
  .then(extractContent)
  .then(storeArticles)
  .then(generateHeadlines)
  .then(storeTopics)
  .commit();

// Execution:
// const run = await dailyDigestWorkflow.createRun();
// const result = await run.start({ inputData: { date: '2026-02-08' } });
```

### Tools

Mastra v1 tools use `createTool` with typed `inputSchema`/`outputSchema`. The `execute` function receives `inputData` directly (not `{ context }`).

```typescript
// apps/server/src/mastra/tools/tavily-search.ts
import { createTool } from '@mastra/core/tools';
import { z } from 'zod';

export const tavilySearchTool = createTool({
  id: 'tavily-search',
  description: 'Search the web for recent articles on a specific topic',
  inputSchema: z.object({
    query: z.string().describe('Search query'),
    timeRange: z.enum(['day', 'week', 'month']).default('day'),
    maxResults: z.number().default(5),
  }),
  outputSchema: z.object({
    results: z.array(z.object({ title: z.string(), url: z.string(), content: z.string() })),
  }),
  execute: async (inputData) => {
    const response = await fetch('https://api.tavily.com/search', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.TAVILY_API_KEY}`,
      },
      body: JSON.stringify({
        query: inputData.query,
        search_depth: 'basic',
        time_range: inputData.timeRange,
        max_results: inputData.maxResults,
        include_raw_content: true,
      }),
    });
    return { results: (await response.json()).results };
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
- Topic types: 'hot' topics displayed prominently, 'normal' topics in standard layout, 'standalone' articles shown as individual items
- Click card → navigate to `/article/:topicId`
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
- LLM section: display current provider info (read-only, configured via ENV — settings-driven override deferred to post-MVP P1)
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

**UI**: ShadCN/ui components with BasaltUI theme (`@basalt-ui` from [jkrumm/basalt-ui](https://github.com/jkrumm/basalt-ui)) for consistent ShadCN + Tailwind CSS styling. Install components via `bunx --bun shadcn@latest add <component>`.

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
    "@sentry/react": "latest",
    "tailwindcss": "^4.0.0",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "@tanstack/router-plugin": "^1.114.0",
    "@tanstack/react-router-devtools": "^1.114.0"
  }
}
```

---

## 8. Infrastructure

### Environment Variables

All config validated centrally with Zod at startup. LLM connection tested on settings save. User overrides from Settings UI persisted to SQLite `settings` table.

```bash
# Required
AUTH_SECRET=              # Shared secret for login
LLM_PROVIDER=google      # google | openai | anthropic | openai-compatible
LLM_MODEL=gemini-2.0-flash-001  # Default model for all operations
LLM_API_KEY=              # API key for the LLM provider
TAVILY_API_KEY=           # Tavily API key (free tier: 1000 credits/mo)

# Optional - LLM
LLM_BASE_URL=             # Custom base URL for LLM API
LLM_MODEL_FAST=           # Fast model for headlines/scoring (defaults to LLM_MODEL)
LLM_MODEL_PRO=            # Pro model for article generation (defaults to LLM_MODEL)

# Optional - Observability
SENTRY_DSN=               # Sentry DSN (optional, no-op if unset)

# Optional - Pipeline Adapters (see docs/PIPELINE.md)
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

ENV NODE_ENV=production
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

**Release workflow**: Semantic release triggered via GitHub Actions `workflow_dispatch` ("Make Release" button). Bumps version based on conventional commits, generates CHANGELOG.md, creates GitHub Release, then builds and pushes Docker image tagged with the version. Uses `commitlint` in CI to validate conventional commit messages.

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
      - run: bunx commitlint --from ${{ github.event.pull_request.base.sha || 'HEAD~1' }} --to HEAD

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

---

## 10. MVP Scope & Implementation Plan

### Phase 1: Project Setup

- [ ] Create project CLAUDE.md for Claude Code integration
- [ ] Initialize Bun monorepo with workspaces
- [ ] Set up `packages/shared` with types
- [ ] Set up `apps/server` with Hono + basic health endpoint
- [ ] Set up `apps/web` with Vite + React + Tailwind
- [ ] Configure Biome (root config)
- [ ] Configure TypeScript (project references)
- [ ] Set up Drizzle ORM + SQLite schema + migrations
- [ ] Dockerfile + docker-compose.yml
- [ ] GitHub Actions CI (lint + typecheck + commitlint + docker build)
- [ ] Semantic release setup (workflow_dispatch trigger)
- [ ] ShadCN/ui + BasaltUI theme setup

### Phase 2: Backend Core

- [ ] Environment config validation (Zod schema, connection testing)
- [ ] Auth middleware (shared secret + cookie + bearer token dual-mode)
- [ ] Settings CRUD endpoints
- [ ] Sources CRUD endpoints
- [ ] LLM model factory (provider-agnostic, fast/pro tier support)
- [ ] RSS feed parser service
- [ ] Hacker News API client
- [ ] Tavily search client
- [ ] Content extraction service (ContentExtractor interface + readability + Tavily chain)
- [ ] Deduplication service (URL normalization + title similarity)
- [ ] Cron scheduling with croner

### Phase 3: AI Pipeline

- [ ] Mastra instance setup
- [ ] Mastra tools (Tavily search, extract, content fetch)
- [ ] Headline Agent (group + score + assign topicType + generate headlines)
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

- [ ] Sentry integration (optional via `SENTRY_DSN` env var, `@sentry/bun` + `@sentry/react`)
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

| Resource           | Cost          | Notes                                    |
|--------------------|---------------|------------------------------------------|
| RSS feeds          | $0            | Unlimited, free                          |
| Hacker News API    | $0            | Unlimited, no auth                       |
| Tavily (free tier) | $0            | 1,000 credits/month                      |
| LLM (Gemini Flash) | ~$1-5         | Daily headlines + ~30 article deep-dives |
| VPS (Hetzner CX22) | ~$4/mo        | 2 vCPU, 4GB RAM, 40GB SSD                |
| **Total**          | **~$5-10/mo** |                                          |

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

---

## 13. Post-MVP Roadmap

Features and improvements deferred from MVP scope, organized by priority. Each item builds on top of the MVP architecture without requiring fundamental changes.

### P1: High Value, Low Effort

**Firecrawl Content Extraction Adapter** (see [`docs/PIPELINE.md`](./PIPELINE.md) §Extension Guide)
- Add `FirecrawlExtractor` to the `ContentExtractor` chain (enabled via `FIRECRAWL_URL` env var)
- `@mendable/firecrawl-js` SDK, ~15 lines of implementation
- Slots between ReadabilityExtractor and TavilyExtractor in the fallback chain
- Handles JS-rendered sites without using Tavily credits

**Mastra AI Studio**
- Enable Mastra's built-in dev UI for debugging agents/workflows locally
- Useful during development to inspect LLM prompts, tool calls, and workflow execution

**AI-Verified Deduplication (Second Pass)**
- Add a focused LLM call for borderline title similarity pairs (0.5-0.7 Dice score)
- "Are these the same story?" prompt with fast model, ~5-10 calls/day
- Reduces false positives without the cost of full pairwise AI comparison

**Settings-Driven LLM Config**
- Allow users to configure LLM provider, model tiers (fast/pro), and API key from the Settings UI
- Test LLM connection before persisting changes
- Override ENV defaults with user preferences from SQLite
- Merge strategy: user overrides win over ENV defaults, all config validated centrally with Zod

### P2: High Value, Medium Effort

**OpenTelemetry / AI Pipeline Observability**
- Mastra has built-in OTel support with GenAI Semantic Conventions (token usage, latency, prompts)
- Enable via `OTEL_EXPORTER_OTLP_ENDPOINT` env var (opt-in, no-op if unset)
- Use HTTP/protobuf exporter (`@opentelemetry/exporter-trace-otlp-proto`) -- gRPC has Bun compatibility issues
- Users point to their own SigNoz/Jaeger/Grafana Tempo instance
- `@hono/otel` middleware for HTTP request tracing
- **Never phone-home** -- provide capability for users to monitor their own instances

**SSR/SSG for Feed Page**
- Hono supports React SSR via `@hono/react-renderer` and `renderToReadableStream()`
- Feed updates once/day, making it a good SSG candidate
- Article pages remain CSR with streaming
- No metaframework needed -- Hono handles it natively

**Additional Data Sources** (see [`docs/PIPELINE.md`](./PIPELINE.md) §Extension Guide)
- Exa neural search adapter (optional, `EXA_API_KEY`, semantic/embedding search)
- GNews API adapter (optional, `GNEWS_API_KEY`, 100 req/day free, non-commercial)
- Perplexity research tool (optional, `PERPLEXITY_API_KEY`, Stage 3 only — answer engine, not URL discovery)
- Reddit RSS adapter (subreddit-specific feeds, no API key needed)
- Each source implements `SourceAdapter`, enabled via per-adapter env var

**Infinite Scroll UX Enhancement**
- Note: cursor-based feed API pagination is included in MVP (see §5)
- This P2 item covers the UX polish: `useInfiniteQuery` with intersection observer for seamless day-by-day loading
- Loading indicators, skeleton states during scroll

### P3: Medium Value, Higher Effort

**Multi-User / Multi-Tenancy**
- Replace single-user shared secret with per-user auth
- Consider Better-Auth for OAuth/credential-based login
- Per-user settings, sources, and feed preferences
- Hono's cross-runtime portability helps if edge deployment is needed later

**Article ImageGen**
- AI-generated header images for articles (DALL-E, Gemini Imagen)
- Stored as static assets in `/app/data/images/`

**Article Syntax Highlighting**
- `rehype-highlight` or `shiki` integration with `streamdown`/markdown renderer
- Code blocks in generated articles rendered with proper syntax highlighting

**GenAI Diagrams in Articles**
- Mermaid diagram generation in article content
- `mermaid` renderer component in the markdown pipeline

**YouTube / Podcast Integration**
- YouTube transcript extraction (transcript API or yt-dlp)
- Podcast RSS with audio-to-text transcription
- Both feed into the same raw articles pipeline

### P4: Nice to Have

**Semantic Release CI/CD Improvements**
- Automated Docker image tagging with semantic versions (v1.2.3)
- CHANGELOG.md auto-generation from conventional commits
- GitHub Release with changelog body

**Advanced Deduplication**
- SimHash or embedding-based dedup for high-volume feeds (>500 articles/day)
- Vector database (e.g., Turso with vector extension) for semantic similarity

**External API**
- Public REST API for feed consumption by external clients
- Bearer token auth (already supported in dual-auth middleware)
- Webhook notifications for new daily digests

**Topic Subscriptions / Alerts**
- User can "watch" specific tags or topics
- Daily email digest option (optional SMTP config)

---

## 14. Decision Log

| # | Decision | Chosen | Alternatives | Why |
|---|----------|--------|-------------|-----|
| 1 | Web framework | Hono | Elysia | Mastra official adapter, SSE maturity, cross-runtime, ecosystem |
| 2 | AI SDK | Vercel AI SDK (v6.x) | TanStack AI (v0.3 alpha) | Production stability, identical Hono integration |
| 3 | Content extraction | Pluggable chain (readability → Tavily) | Hardcoded if/else | Same effort, extensible for Firecrawl later |
| 4 | Deduplication | URL normalization + Dice coefficient | AI-based, embeddings | Instant, free, sufficient for MVP volume |
| 5 | Observability (MVP) | Sentry (optional via env var) | SigNoz/OTel, nothing | 30min setup, no-op if unset, OSS sponsorship available |
| 6 | Observability (post-MVP) | Mastra OTel export | Sentry only | GenAI semantic conventions, AI pipeline tracing |
| 7 | Auth | Cookie + Bearer dual-mode | Cookie only | Supports both web SPA and external API consumers |
| 8 | Model tiers | Fast + Pro via env vars | Single model | Headlines need speed, articles need quality |
| 9 | Topic types | hot / normal / standalone | Single type | Better UX, one column + prompt tweak |
| 10 | Config storage | SQLite settings table | Config file | Single source of truth, already have DB |
| 11 | Phone-home telemetry | Never | Opt-in to author's SigNoz | OSS community trust, provide hooks not monitoring |
| 12 | Structured logging | Pino + hono-pino | console.log, winston, bunyan | Fastest, NDJSON stdout, Hono/Sentry integration, shared schema |
| 13 | Local log viewer | Logdy (browser UI) | pino-pretty only, Kibana | Zero config, stdin pipe, auto-columns from JSON, no infra |
| 14 | RSS parsing | `@extractus/feed-extractor` | `rss-parser`, `feedsmith` | Official Bun support, ESM-first, actively maintained, rss-parser is stale (2+ years no release) |
| 15 | HTML DOM (for Readability) | `linkedom` | `jsdom`, `happy-dom` | 90% smaller, 3x faster, proven Readability compat, no Bun issues |
| 16 | String similarity | `fast-dice-coefficient` | `string-similarity`, `CmpStr` | `string-similarity` is abandoned (5 years), same Dice algorithm, maintained |
| 17 | Streaming markdown | `streamdown` (Vercel) | `react-markdown` + `remark-gfm` | Built for AI streaming (unterminated blocks, token-by-token), GFM included, React 19 |
| 18 | Auth token format | JWT (signed with key derived from `AUTH_SECRET`, no expiry) + Bearer `AUTH_SECRET` | Random session token, expiring JWT | JWT survives restarts (deterministic key), no expiry (single-user), raw secret as bearer (Glance, Obsidian) |
| 19 | Article streaming hook | `useCompletion` | `useChat` | One-shot generation, not conversational — useChat adds unnecessary multi-turn state |
| 20 | LLM config (MVP) | ENV-only | Settings UI override | Simpler for MVP, settings-driven override deferred to post-MVP P1 |
