# OpenNews - Product Requirements

> Personal AI-powered news aggregator. Single Docker container. Provider-agnostic LLM.
> Self-hosted, open-source, privacy-first.

---

## 1. Vision

OpenNews is a self-hosted, AI-powered news aggregator that delivers a personalized daily news feed. It scrapes configured sources (RSS feeds, Hacker News, Tavily web search), deduplicates and groups articles by topic, generates personalized headlines using an LLM, and offers on-demand deep-dive article generation from multiple sources.

## 2. Core User Flows

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

## 3. Non-Goals (MVP)

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

## 4. MVP Scope

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
- [ ] LLM model factory (provider-agnostic, single model for MVP)
- [ ] RSS feed parser service
- [ ] Hacker News API client
- [ ] Tavily search client
- [ ] Content extraction service (ContentExtractor interface + readability + Tavily chain)
- [ ] Deduplication service (URL normalization + title similarity)
- [ ] Cron scheduling with croner

### Phase 3: AI Pipeline

- [ ] Mastra instance setup (Article Agent only)
- [ ] Mastra tools (Tavily search, extract, content fetch)
- [ ] Headline generation service (AI SDK generateObject, not Mastra agent)
- [ ] Daily Digest Service (plain async function, not Mastra workflow)
- [ ] Article Agent (deep-dive generation with compression phase)
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

## 5. Default RSS Feeds (Starter Pack)

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

## 6. Cost Analysis

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

## 7. Post-MVP Roadmap

Features and improvements deferred from MVP scope, organized by priority. Each item builds on top of the MVP architecture without requiring fundamental changes.

### P1: High Value, Low Effort

**Firecrawl Content Extraction Adapter** (see [`PIPELINE.md`](./PIPELINE.md) §Extension Guide)
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

**Additional Data Sources** (see [`PIPELINE.md`](./PIPELINE.md) §Extension Guide)
- Exa neural search adapter (optional, `EXA_API_KEY`, semantic/embedding search)
- GNews API adapter (optional, `GNEWS_API_KEY`, 100 req/day free, non-commercial)
- Perplexity research tool (optional, `PERPLEXITY_API_KEY`, Stage 3 only -- answer engine, not URL discovery)
- Reddit RSS adapter (subreddit-specific feeds, no API key needed)
- Each source implements `SourceAdapter`, enabled via per-adapter env var

**Infinite Scroll UX Enhancement**
- Note: cursor-based feed API pagination is included in MVP (see [`ARCHITECTURE.md`](./ARCHITECTURE.md) §API)
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
