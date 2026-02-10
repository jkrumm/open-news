# OpenNews - Architecture Decision Records

> All architectural decisions and their rationale.
> For technical implementation details, see [`ARCHITECTURE.md`](./ARCHITECTURE.md).

---

## ADR-001: AI Framework - Mastra as Library

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

## ADR-002: LLM Provider Strategy - Provider-Agnostic via AI SDK

**Decision**: Use the Vercel AI SDK's provider system for LLM abstraction. User configures their preferred provider via environment variables.

**Challenged: TanStack AI vs Vercel AI SDK** (Feb 2026)

TanStack AI (`@tanstack/ai` v0.3.1) is explicitly alpha with acknowledged bugs and breaking changes. Vercel AI SDK is at v6.x, production-proven. Both work identically with Hono (standard `Response` objects). The `useChat` APIs are nearly identical -- migration to TanStack AI later is cheap if it reaches v1.0. Sticking with Vercel AI SDK for stability.

**Model Tiers**: MVP uses a single model via `LLM_MODEL` env var for all operations. Post-MVP P1: Two-tier routing with `LLM_MODEL_FAST` (headlines/grouping, cheaper) and `LLM_MODEL_PRO` (article synthesis, higher quality), both falling back to `LLM_MODEL` if not set.

**Configuration source of truth (MVP)**: ENV vars are the sole config source for LLM provider/model/key. Settings UI for LLM config is deferred to post-MVP (see P1 roadmap). User preferences (profile, interests, news style, sources) live in the `settings` table. All config validated with Zod at startup.

## ADR-003: Data Sources - RSS + Tavily + Hacker News

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

**Post-MVP: Additional sources** (Exa, GNews, Serper, etc.) can be added later as optional source adapters via the `SourceAdapter` interface. See [`PIPELINE.md`](./PIPELINE.md) for adapter interfaces, registry, and extension guide.

**RSS is the backbone**: Free, reliable, user-controlled. Combined with Tavily for discovery and HN for tech community picks, this covers the MVP without paid API subscriptions.

**RSS parsing**: Use `@extractus/feed-extractor` instead of `rss-parser`. It has official Bun support, ESM-first design, supports RSS/Atom/RDF/JSON feeds, and is actively maintained (last release Oct 2025). `rss-parser` has not been released in 2+ years and is CJS-only.

**Content extraction**: See ADR-007 and [`PIPELINE.md`](./PIPELINE.md) for the extraction chain architecture.

## ADR-004: Database - SQLite via bun:sqlite + Drizzle ORM

**Decision**: Use Bun's built-in SQLite driver (`bun:sqlite`) with Drizzle ORM for type-safe queries and migrations.

**Rationale**:
- Single-file database - perfect for a single Docker container
- `bun:sqlite` is 3-6x faster than `better-sqlite3`, zero additional dependencies
- WAL mode enables concurrent reads during cron job writes
- Drizzle provides type-safe queries, migrations, and schema management
- No external database server needed

**Volume mount**: The `/app/data` directory is mounted as a Docker volume for persistence.

## ADR-005: Frontend - React SPA with Vite, served by Hono

**Decision**: Build the frontend as a React SPA using Vite. In production, serve the built static files from the Hono backend. In development, use Vite's dev server with a proxy to the backend.

**Rationale**:
- Vite provides HMR, React Fast Refresh, and a mature plugin ecosystem
- Bun runs Vite natively (no Node.js needed)
- Production: Hono serves `/assets/*` as static files and `/*` as SPA fallback
- Single port, single process in production

**SSR/SSG**: Post-MVP consideration. CSR with TanStack Query caching is sufficient for MVP -- the feed updates once/day, so client-side caching is effective. Hono has SSR capabilities (`@hono/react-renderer`, HonoX) if needed later without a metaframework.

**Streaming**: Use `@ai-sdk/react`'s `useCompletion` hook for streaming LLM-generated articles (one-shot, not conversational). The Hono backend uses Mastra's `agent.stream()` with `toDataStreamResponse()`.

**Styling**: Tailwind CSS v4 (CSS-first config, no `tailwind.config.js`).

**Challenged: TanStack Router vs react-router-dom** (Feb 2026)

TanStack Router wins for this project:
1. **Type Safety**: Automatic type inference for route params, search params, and loader data.
2. **Search Param Validation**: Built-in Zod schema validation for URL search params (`validateSearch`), crucial for feed filtering and pagination.
3. **File-Based Routing**: Vite plugin (`@tanstack/router-plugin`) auto-generates routes from file structure with code splitting.
4. **Modern DX**: Built for React 19, devtools, and better integration with TanStack Query.
5. **Migration Cost**: Low - similar API surface to react-router-dom v7, but with superior type safety.

## ADR-006: Cron Scheduling - croner

**Decision**: Use `croner` for in-process cron scheduling instead of Mastra's Inngest integration or external cron services.

**Rationale**:
- Inngest requires an external service (adds infrastructure complexity)
- `croner` is a modern, ESM-compatible cron library that works with Bun
- Runs in the same process - no external dependencies
- Supports timezone-aware scheduling

## ADR-007: Content Extraction - Readability + Tavily Fallback

**Decision**: Use `@mozilla/readability` with `linkedom` as the primary content extraction method. Fall back to Tavily Extract for URLs that fail.

**Rationale**:
- Readability is the industry standard (used in Firefox Reader View)
- `linkedom` is 90% smaller than `jsdom` (~235KB vs ~20MB), 3x faster, 3x less heap usage
- `linkedom` is proven compatible with Readability in production (used by readability-js Rust crate)
- Free and unlimited - no API costs
- Handles most static HTML news sites well
- Tavily Extract handles JS-rendered content and paywalled sites as a fallback

**Cost**: Tavily Extract costs 1 credit per 5 URLs. With 1,000 free credits/month, budget ~200 fallback extractions (1,000 URLs).

**Pluggable Extractor Architecture**: `ContentExtractor` interface with a config-driven fallback chain. See [`PIPELINE.md`](./PIPELINE.md) for full adapter interfaces, chain behavior, and registry implementation.

**Post-MVP**: Add FirecrawlExtractor (`@mendable/firecrawl-js` SDK) for self-hosted instances. Skip Crawl4AI -- Python-first, no official JS SDK.

## ADR-008: Deduplication - URL Normalization + Title Similarity

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

## ADR-009: Structured Logging - Pino + hono-pino + Logdy

**Decision**: Use Pino as the single structured logging layer across the entire application. Shared logger factory in `packages/shared`, request-scoped logging via `hono-pino` middleware, Sentry bridge via official `pinoIntegration`.

**Architecture**:

| Layer | Tool | Purpose |
|-------|------|---------|
| Logger factory | `packages/shared/src/logger.ts` | Shared Pino config, `createLogger(service)` |
| HTTP request logging | `hono-pino` middleware | requestId (UUID), responseTime, method, path, status |
| Error bridge | `Sentry.pinoIntegration()` | Forward `error`/`fatal` Pino logs to Sentry |
| Local dev viewing | `pino-pretty` (terminal) + Logdy (browser UI) | Human-readable exploration |
| Production | Raw NDJSON to stdout | Docker captures via logging driver |

**Why Pino**: JSON structured logging is the standard for Docker/cloud. Pino is the fastest Node/Bun logger, outputs NDJSON to stdout (what Docker expects), and has first-class Hono and Sentry integrations. `console.log` is unstructured and not queryable.

**Why Logdy**: Standalone binary (`brew install logdy`), reads from stdin -- no Pino transport needed. Provides a browser UI with auto-generated columns from JSON fields, faceted filtering, search. Complementary to `pino-pretty` (terminal vs browser).

---

## Decision Log

| # | Decision | Chosen | Alternatives | Why |
|---|----------|--------|-------------|-----|
| 1 | Web framework | Hono | Elysia | Mastra official adapter, SSE maturity, cross-runtime, ecosystem |
| 2 | AI SDK | Vercel AI SDK (v6.x) | TanStack AI (v0.3 alpha) | Production stability, identical Hono integration |
| 3 | Content extraction | Pluggable chain (readability -> Tavily) | Hardcoded if/else | Same effort, extensible for Firecrawl later |
| 4 | Deduplication | URL normalization + Dice coefficient | AI-based, embeddings | Instant, free, sufficient for MVP volume |
| 5 | Observability (MVP) | Sentry (optional via env var) | SigNoz/OTel, nothing | 30min setup, no-op if unset, OSS sponsorship available |
| 6 | Observability (post-MVP) | Mastra OTel export | Sentry only | GenAI semantic conventions, AI pipeline tracing |
| 7 | Auth | Cookie + Bearer dual-mode | Cookie only | Supports both web SPA and external API consumers |
| 8 | Model tiers (MVP) | Single model via LLM_MODEL | Fast + Pro tiers | Simpler for MVP; two-tier routing deferred to post-MVP P1 |
| 9 | Topic types | hot / normal / standalone | Single type | Better UX, one column + prompt tweak |
| 10 | Config storage | SQLite settings table | Config file | Single source of truth, already have DB |
| 11 | Phone-home telemetry | Never | Opt-in to author's SigNoz | OSS community trust, provide hooks not monitoring |
| 12 | Structured logging | Pino + hono-pino | console.log, winston, bunyan | Fastest, NDJSON stdout, Hono/Sentry integration, shared schema |
| 13 | Local log viewer | Logdy (browser UI) | pino-pretty only, Kibana | Zero config, stdin pipe, auto-columns from JSON, no infra |
| 14 | RSS parsing | `@extractus/feed-extractor` | `rss-parser`, `feedsmith` | Official Bun support, ESM-first, actively maintained |
| 15 | HTML DOM (for Readability) | `linkedom` | `jsdom`, `happy-dom` | 90% smaller, 3x faster, proven Readability compat |
| 16 | String similarity | `fast-dice-coefficient` | `string-similarity`, `CmpStr` | `string-similarity` abandoned (5 years), same algorithm |
| 17 | Streaming markdown | `streamdown` (Vercel) | `react-markdown` + `remark-gfm` | Built for AI streaming, GFM included, React 19 |
| 18 | Auth token format | JWT (derived key, no expiry) + Bearer | Random session token, expiring JWT | Survives restarts, single-user, raw secret as bearer |
| 19 | Article streaming hook | `useCompletion` | `useChat` | One-shot generation, not conversational |
| 20 | LLM config (MVP) | ENV-only | Settings UI override | Simpler for MVP, settings-driven override deferred to P1 |
