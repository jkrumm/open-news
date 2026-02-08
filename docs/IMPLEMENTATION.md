# OpenNews - Implementation Plan

> Task breakdown for iterative implementation with Claude Code.
> Each task is self-contained and references the relevant SPEC.md sections.

## Workflow Per Task

1. Pick next unblocked task
2. Research (Tavily/Context7) if touching unfamiliar libraries
3. Review surrounding code before writing — maybe use /explore skill from Claude Code
4. Implement
5. Keep docs in sync — if the implementation deviates from or refines the plan:
   - `docs/SPEC.md` — update ADRs, schemas, API design, or dependency lists
   - `CLAUDE.md` — update project conventions, scripts, architecture notes
   - `README.md` — update setup instructions, env vars, or usage docs
6. `/code-quality` → `/commit`
7. Check off task below

## Notation

- `[SPEC §N]` = Reference to SPEC.md section number
- `depends: #N` = Must complete task N first
- `research:` = Libraries/APIs to look up before starting

---

## Phase 1: Project Scaffold

### 1.1 — Initialize monorepo and workspace structure
`[SPEC §3 Monorepo Structure]`

- Initialize root `package.json` with Bun workspaces (`apps/*`, `packages/*`)
- Create directory structure: `apps/server/`, `apps/web/`, `packages/shared/`
- Create `packages/shared/package.json` + `src/index.ts` (empty export)
- Create `apps/server/package.json` + `src/index.ts` (placeholder)
- Create `apps/web/package.json` + `src/main.tsx` (placeholder)
- `bun install` to verify workspace resolution
- research: `bun workspaces` configuration

### 1.2 — Configure TypeScript with project references
`[SPEC §3]` · depends: #1.1

- Root `tsconfig.json` with project references to all three packages
- `packages/shared/tsconfig.json` — strict, composite, declaration
- `apps/server/tsconfig.json` — strict, references shared
- `apps/web/tsconfig.json` — strict, references shared, JSX react-jsx
- Verify `tsc -b` passes from root
- research: `typescript project references monorepo`

### 1.3 — Configure Biome
`[SPEC §3]` · depends: #1.1

- Root `biome.json` with formatting + linting rules
- Add `check` and `check:fix` scripts to root `package.json`
- Verify `bun run check` passes on empty project
- research: `biome configuration` (Context7)

### 1.4 — Set up shared package with types, schema, and logger
`[SPEC §4 Data Model, §ADR-009]` · depends: #1.2

- `packages/shared/src/types.ts` — domain types: `SourceType`, `TopicType`, `NewsStyle`, API request/response types
- `packages/shared/src/schema.ts` — Zod schemas for API validation (settings, sources, auth)
- `packages/shared/src/logger.ts` — Pino logger factory: `createLogger(service)` with shared config
  - `NODE_ENV !== 'production'` → `pino-pretty` transport (colored, human-readable)
  - Production → raw NDJSON to stdout (Docker-ready)
  - `LOG_LEVEL` env var support (default: debug in dev, info in prod)
  - ISO timestamp, child logger per service
- Install `pino` in shared, `pino-pretty` as devDependency
- Export everything from `packages/shared/src/index.ts`
- Verify `tsc -b` still passes
- research: `pino logger setup` (Context7), `pino-pretty`

### 1.5 — Set up Hono server with health endpoint + structured logging
`[SPEC §3, §5 API Design, §ADR-009]` · depends: #1.4

- Install `hono`, `hono-pino` in `apps/server`
- `apps/server/src/index.ts` — Hono app with `pinoLogger` middleware + `/api/health` endpoint
  - `hono-pino` middleware: requestId (UUID), responseTime, method, path, status
  - Access logger in routes via `c.var.logger`
- Add `dev` script using `bun --hot`
- Add `dev:logdy` script: `bun run dev | logdy --fallthrough` (pipe to Logdy browser UI)
- Verify server starts, health endpoint returns `{ status: 'ok' }`, request logs appear as structured JSON
- research: `hono bun setup` (Context7), `hono-pino` middleware

### 1.6 — Set up Vite + React + Tailwind
`[SPEC §ADR-005, §8 Frontend]` · depends: #1.2

- Install React 19, Vite, Tailwind v4, react-router-dom v7 in `apps/web`
- `apps/web/index.html` + `vite.config.ts` with proxy to backend
- `apps/web/src/main.tsx` → `App.tsx` with react-router setup (3 routes: `/`, `/article/:id`, `/settings`)
- `apps/web/src/styles/globals.css` with Tailwind v4 imports
- Placeholder route components
- `dev` script for Vite dev server
- Verify HMR works and proxy hits backend health endpoint
- research: `tailwind css v4 setup vite` (Context7), `react-router-dom v7`

### 1.7 — Set up Drizzle ORM + SQLite schema
`[SPEC §4 Data Model, §ADR-004]` · depends: #1.4

- Install `drizzle-orm`, `drizzle-kit` in `apps/server`
- `apps/server/src/db/schema.ts` — full schema from SPEC (settings, sources, rawArticles, dailyTopics, tags, topicTags, topicSources, generatedArticles) with indexes
- `apps/server/src/db/index.ts` — database connection with WAL mode, pragmas
- `apps/server/drizzle.config.ts`
- Generate initial migration, verify it applies
- research: `drizzle-orm bun:sqlite` (Context7)

### 1.8 — ShadCN/ui + BasaltUI theme setup
`[SPEC §8 Key Libraries]` · depends: #1.6

- Install ShadCN with `bunx --bun shadcn@latest init`
- Configure BasaltUI theme (import CSS from `@basalt-ui`)
- Install initial components: button, input, card, dialog
- Verify components render correctly with theme
- research: `shadcn ui vite react` setup, BasaltUI CSS

### 1.9 — Dockerfile + docker-compose.yml
`[SPEC §9 Docker Configuration]` · depends: #1.5, #1.6

- Multi-stage Dockerfile: install → build web → build server → runtime
- `docker-compose.yml` with volume mount for `/app/data`
- `.dockerignore`
- Verify `docker build` succeeds and container starts
- NOTE: Local dev only for now — no GHCR push until MVP is feature-complete
- research: `bun dockerfile production` best practices

### 1.10 — GitHub Actions CI (lint + typecheck only)
`[SPEC §9 CI/CD]` · depends: #1.3

- `.github/workflows/ci.yml` — biome check + tsc -b + commitlint
- `commitlint.config.js` — conventional commits validation config
- No Docker build/push in CI yet — defer container registry to post-MVP ship
- research: `github actions bun setup`, `commitlint conventional commits config`

### 1.11 — Create CLAUDE.md + README.md
depends: #1.5

- `CLAUDE.md` — project-specific conventions (scripts, file patterns, architecture notes)
- `README.md` — project description, setup instructions, env vars, Docker usage
- Both will evolve as implementation progresses

---

## Phase 2: Backend Core

### 2.1 — Environment config validation
`[SPEC §9 Environment Variables, §ADR-002 Config]` · depends: #1.7

- `apps/server/src/config.ts` — Zod schema for all env vars (required + optional)
- Load and validate at startup, fail fast with clear error messages
- Export typed `AppConfig` object
- Support defaults (PORT=3000, TIMEZONE=UTC, etc.)

### 2.2 — Auth middleware (dual-mode)
`[SPEC §5 Authentication]` · depends: #2.1

- `apps/server/src/routes/auth.ts` — login, check, logout endpoints
- `apps/server/src/middleware/auth.ts` — cookie + bearer token middleware
- Login: validate secret → create signed session token → set HTTP-only cookie
- Middleware: check cookie first, fall back to `Authorization: Bearer` header
- Protected routes: all `/api/v1/*` except `/auth/login` and `/health`
- research: `hono cookie middleware`, `hono jwt`

### 2.3 — Settings CRUD
`[SPEC §5 REST Endpoints]` · depends: #2.2, #1.7

- `apps/server/src/routes/settings.ts` — GET + PUT `/api/v1/settings`
- Single-row pattern: upsert on PUT
- Validate with shared Zod schemas
- Return typed response

### 2.4 — Sources CRUD
`[SPEC §5 REST Endpoints]` · depends: #2.2, #1.7

- `apps/server/src/routes/sources.ts` — full CRUD for `/api/v1/sources`
- Validate URL format, source type
- Seed default RSS feeds on first startup (if sources table empty)
- research: default feeds list from `[SPEC §11]`

### 2.5 — LLM model factory
`[SPEC §ADR-002, §6]` · depends: #2.1

- `apps/server/src/model.ts` — `createModel(tier: 'fast' | 'pro')` function
- Install AI SDK packages: `ai`, `@ai-sdk/google`, `@ai-sdk/openai`, `@ai-sdk/anthropic`
- Provider switch based on `LLM_PROVIDER` env var
- Tier resolution: `LLM_MODEL_FAST` → `LLM_MODEL` fallback, `LLM_MODEL_PRO` → `LLM_MODEL` fallback
- research: `vercel ai sdk provider setup` (Context7)

### 2.6 — RSS feed parser service
`[SPEC §ADR-003, §3 Data Flow]` · depends: #1.7

- `apps/server/src/services/rss.ts`
- Install `@extractus/feed-extractor` (ESM-first, official Bun support, actively maintained)
- Fetch all enabled RSS sources, parse items
- Implement conditional fetching manually (ETag/If-Modified-Since headers via `fetchOptions`)
- Return normalized raw article objects
- research: `@extractus/feed-extractor` API and usage

### 2.7 — Hacker News API client
`[SPEC §ADR-003]` · depends: #1.7

- `apps/server/src/services/hackernews.ts`
- Fetch top 50 stories from HN API (`/v0/topstories.json` + `/v0/item/{id}.json`)
- Parallel item fetches with concurrency limit
- Return normalized raw article objects
- research: `hacker news api` documentation

### 2.8 — Tavily search client
`[SPEC §ADR-003]` · depends: #2.1

- `apps/server/src/services/tavily.ts`
- Search based on user's configured `searchQueries` from settings
- Return normalized raw article objects
- research: `tavily search api` (Context7 or web)

### 2.9 — Content extraction service
`[SPEC §ADR-007]` · depends: #2.1

- `apps/server/src/services/extractor.ts`
- `ContentExtractor` interface + `buildExtractorChain()` factory
- `ReadabilityExtractor` — `@mozilla/readability` + `linkedom` (90% smaller than jsdom, proven Readability compat)
- `TavilyExtractor` — Tavily Extract API fallback
- Chain tries extractors in order, returns first success
- Install `@mozilla/readability`, `linkedom`
- research: `@mozilla/readability linkedom` usage, `parseHTML` from linkedom

### 2.10 — Deduplication service
`[SPEC §ADR-008]` · depends: #1.7

- `apps/server/src/services/dedup.ts`
- URL normalization: strip tracking params, normalize www/protocol/trailing slash
- Title similarity: Dice coefficient via `fast-dice-coefficient` (the `string-similarity` package is abandoned)
- Compare against articles from last 48 hours
- Install `fast-dice-coefficient`

### 2.11 — Ingestion orchestrator + cron scheduling
`[SPEC §3 Data Flow, §ADR-006]` · depends: #2.6, #2.7, #2.8, #2.9, #2.10

- `apps/server/src/services/ingestion.ts` — orchestrates: fetch all sources → dedup → extract content → store
- `apps/server/src/services/cron.ts` — croner setup, calls ingestion on schedule
- Install `croner`
- Wire into server startup
- Add manual trigger endpoint: `POST /api/v1/admin/trigger-digest`
- Use structured Pino logging throughout: `logger.info({ sourceCount, newArticles }, 'Ingestion complete')`
- research: `croner` API

### 2.12 — Feed query endpoint + tags endpoint
`[SPEC §5 REST Endpoints]` · depends: #1.7

- `apps/server/src/routes/feed.ts` — `GET /api/v1/feed` with cursor-based pagination
  - Query `daily_topics` joined with tags and source counts
  - `?cursor=2026-02-07` (exclusive, returns days before cursor)
  - `?limit=3` (default: 3 days)
  - `?tag=ai` (optional tag filter)
  - Returns `{ days: DayWithTopics[], nextCursor?: string }`
- `apps/server/src/routes/tags.ts` — `GET /api/v1/tags` returns all tags (no colors for MVP)

---

## Phase 3: AI Pipeline

### 3.1 — Mastra instance setup
`[SPEC §6 Mastra Configuration]` · depends: #2.5

- Install `@mastra/core`
- `apps/server/src/mastra/index.ts` — Mastra instance with agents and workflows
- Import from `@mastra/core/mastra` (v1 subpath export)
- Verify Mastra initializes without errors
- research: `@mastra/core` v1 setup (Context7)

### 3.2 — Mastra tools (Tavily + content fetch)
`[SPEC §6 Tools]` · depends: #3.1, #2.9

- `apps/server/src/mastra/tools/tavily-search.ts` — Tavily search as Mastra tool
- `apps/server/src/mastra/tools/tavily-extract.ts` — Tavily extract as Mastra tool
- `apps/server/src/mastra/tools/fetch-content.ts` — ContentExtractor chain as Mastra tool
- v1 API: `createTool` from `@mastra/core/tools`, `execute` receives `inputData` directly (not `{ context }`)
- Add `inputSchema` + `outputSchema` (Zod) to each tool
- research: `mastra createTool` v1 API (Context7)

### 3.3 — Headline Agent
`[SPEC §6 Headline Agent]` · depends: #3.1

- `apps/server/src/mastra/agents/headline-agent.ts`
- `Agent` from `@mastra/core/agent`, uses `createModel('fast')`
- Structured JSON output via `agent.generate(prompt, { structuredOutput: { schema } })`
- Define Zod output schema: groups, headlines, summaries, scores, tags, topicType
- Access typed result via `response.object`
- research: `mastra agent structured output` v1 (Context7)

### 3.4 — Daily Digest Workflow
`[SPEC §6 Daily Digest Workflow]` · depends: #3.2, #3.3, #2.11

- `apps/server/src/mastra/workflows/daily-digest.ts`
- v1 API: `createWorkflow`/`createStep` from `@mastra/core/workflows`
- Steps chained via `.then()`, finalized with `.commit()`
- Each step has typed `inputSchema`/`outputSchema` (Zod), `execute` receives `{ inputData, mastra }`
- Steps: fetchSources → dedup → extract → storeRaw → generateHeadlines → storeTopics
- Wire workflow into cron job and manual trigger endpoint
- Execution: `workflow.createRun()` then `run.start({ inputData: { date } })`
- research: `mastra createWorkflow createStep` v1 (Context7)

### 3.5 — Article Agent + SSE streaming
`[SPEC §6 Article Agent, §5 SSE Streaming]` · depends: #3.2

- `apps/server/src/mastra/agents/article-agent.ts`
- `Agent` from `@mastra/core/agent`, uses `createModel('pro')`, has access to all 3 tools
- `apps/server/src/routes/article.ts` — endpoints:
  - `GET /api/v1/article/:topicId` — return cached or 404
  - `POST /api/v1/article/:topicId/generate` — SSE stream via `agent.stream()` + `toDataStreamResponse()`
  - `DELETE /api/v1/article/:topicId/cache` — invalidate cache
- Cache completed article to `generated_articles` table after stream completes
- research: `mastra agent stream toDataStreamResponse` v1 (Context7)

---

## Phase 4: Frontend

### 4.1 — API client + auth state
`[SPEC §8 Hooks, §5 Auth]` · depends: #2.2, #1.6

- `apps/web/src/lib/api.ts` — fetch wrapper with cookie auth, error handling
- `apps/web/src/hooks/use-auth.ts` — login, logout, auth check
- `apps/web/src/routes/Login.tsx` — login form (single secret input)
- TanStack Query setup (`QueryClientProvider`)
- Protected route wrapper (redirect to `/login` if unauthenticated)
- Install `@tanstack/react-query`

### 4.2 — Settings page
`[SPEC §8 Settings Page]` · depends: #4.1, #2.3

- `apps/web/src/routes/Settings.tsx`
- `apps/web/src/components/SettingsForm.tsx` — profile fields, news style, language, topics
- `apps/web/src/hooks/use-settings.ts` — TanStack Query mutations for settings CRUD
- Source management section (add/edit/delete/toggle RSS feeds)
- Form validation with shared Zod schemas

### 4.3 — Feed page
`[SPEC §8 Feed Page]` · depends: #4.1, #3.4, #2.12

- `apps/web/src/routes/Feed.tsx` — daily feed layout
- `apps/web/src/components/DaySection.tsx` — date header + topic cards
- `apps/web/src/components/TopicCard.tsx` — headline, summary, source count, tags, relevance, topicType styling
- `apps/web/src/components/TagFilter.tsx` — clickable tag pills
- `apps/web/src/hooks/use-feed.ts` — feed fetching with cursor pagination + tag filter
- `GET /api/v1/feed?cursor=&limit=3&tag=` integration (cursor-based pagination from day one)
- `GET /api/v1/tags` for filter bar
- `useInfiniteQuery` for loading more days on scroll

### 4.4 — Article page (streaming markdown)
`[SPEC §8 Article Page, §5 SSE]` · depends: #4.1, #3.5

- `apps/web/src/routes/Article.tsx` — article view with streaming
- `apps/web/src/components/ArticleView.tsx` — markdown renderer using `streamdown`
- Install `streamdown` (Vercel's AI-streaming markdown renderer, built-in GFM), `@ai-sdk/react`
- Use `useCompletion` (not `useChat` — article generation is one-shot, not conversational)
- Cached: render immediately. Not cached: POST to generate, stream tokens via `useCompletion`
- Refresh button to invalidate cache and regenerate
- `apps/web/src/components/SourceChip.tsx` — source attribution

### 4.5 — Responsive design + layout polish
depends: #4.2, #4.3, #4.4

- `apps/web/src/App.tsx` — app shell with navigation (header/sidebar)
- Mobile-responsive breakpoints for all pages
- Consistent spacing, typography, color scheme via BasaltUI tokens
- Dark/light mode if BasaltUI supports it

---

## Phase 5: Polish + Ship

### 5.1 — Sentry integration + Pino bridge
`[SPEC §Decision Log #5, §ADR-009]` · depends: #2.1, #4.1

- Install `@sentry/bun` (server) + `@sentry/react` (web)
- Initialize only if `SENTRY_DSN` env var is set (no-op otherwise)
- Server: `Sentry.pinoIntegration()` — bridges Pino `error`/`fatal` logs to Sentry error events
- Server: global error handler for uncaught exceptions
- Web: React error boundary with Sentry reporting
- research: `@sentry/bun pinoIntegration` (Sentry docs), `@sentry/react setup`

### 5.2 — Error handling + loading states
depends: #4.3, #4.4

- Global API error handling (toast notifications or error banner)
- React error boundaries per route
- Skeleton loading states for feed page and article page
- Empty states (no topics yet, no settings configured)

### 5.3 — Onboarding flow + seed data
`[SPEC §11 Default RSS Feeds]` · depends: #2.4

- On first startup: seed default RSS feeds from SPEC §11
- Settings page: detect empty profile, show onboarding prompt
- First-run UX: guide user through profile + LLM config + trigger first digest

### 5.4 — Admin status page
`[SPEC §5 Admin Endpoints]` · depends: #2.11

- `GET /api/v1/admin/status` — last digest time, article count, source count, next scheduled run
- Display on settings page or dedicated admin section
- Manual digest trigger button

### 5.5 — Final README.md + documentation
depends: #5.3

- Complete README with: screenshots, setup guide, Docker instructions, env var reference, architecture overview
- Ensure CLAUDE.md reflects final project conventions
- License file (MIT or similar)
