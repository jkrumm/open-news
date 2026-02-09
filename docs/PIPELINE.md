# OpenNews - Pipeline Architecture

> Core news pipeline: source discovery, content extraction, and research tools.
> For system architecture, API design, and infrastructure, see [`SPEC.md`](./SPEC.md).

---

## Overview

OpenNews processes news through three pipeline stages. Each stage uses **adapter interfaces** — small, focused contracts that decouple the pipeline from specific providers. Adapters are enabled/disabled by environment variables, allowing users to mix free and paid services.

```
Stage 1: SOURCE DISCOVERY          Stage 2: CONTENT EXTRACTION         Stage 3: RESEARCH TOOLS
"Find new article URLs"            "Get full text from URL"            "Find more during deep-dive"

Scheduled (daily cron)             On-demand per article               On-demand per Article Agent call

Adapters:                          Adapters (chain/fallback):          Mastra tools wrapping Stage 1+2:
├── RssSourceAdapter               ├── ReadabilityExtractor (free)     ├── tavily-search tool
├── HackerNewsSourceAdapter        ├── TavilyExtractor (paid)          ├── fetch-content tool
├── TavilySearchSourceAdapter      ├── FirecrawlExtractor (post-MVP)   └── tavily-extract tool
├── ExaSourceAdapter (post-MVP)    └── Crawl4AIExtractor (post-MVP)
└── ...more post-MVP
```

**Key design principle**: Stage 3 tools are **thin wrappers** around Stage 1/2 adapter instances. No duplicated fetch/extraction logic.

---

## Mental Model: Three Pipeline Stages

### Stage 1: Source Discovery

**Goal**: Find new article URLs from configured sources.

Runs on a daily cron schedule. Each adapter implements `SourceAdapter` and returns `DiscoveredArticle[]`. All adapters run in parallel; results are merged and deduplicated downstream.

| Adapter | Source | Cost | Auth | Notes |
|---------|--------|------|------|-------|
| `RssSourceAdapter` | RSS/Atom/RDF/JSON feeds | Free | None | Backbone. User controls sources. Conditional fetch via ETag/If-Modified-Since. |
| `HackerNewsSourceAdapter` | HN Firebase API | Free | None | Top 50 stories. `score` field used as quality signal. |
| `TavilySearchSourceAdapter` | Tavily Search API | Free tier (1K credits/mo) | `TAVILY_API_KEY` | Topic-based discovery. Finds articles RSS might miss. |

**Post-MVP adapters**:
- `ExaSourceAdapter` — Neural/embedding search. Good complement to Tavily for semantic discovery.
- `GNewsSourceAdapter` — 100 req/day free, non-commercial license.
- `SerperSourceAdapter` — Google SERP results.

**Not a SourceAdapter**: Perplexity returns LLM-synthesized answers + citations, not raw URLs. It's an answer engine useful for Stage 3 research, not Stage 1 URL discovery.

### Stage 2: Content Extraction

**Goal**: Get full article text from a URL.

Runs on-demand during ingestion (for articles where RSS only provides a snippet) and during Article Agent deep-dives. Extractors implement `ContentExtractor` and are tried in chain order — first success wins.

| Extractor | Method | Cost | Notes |
|-----------|--------|------|-------|
| `ReadabilityExtractor` | `@mozilla/readability` + `linkedom` | Free | Primary. Handles ~95% of static HTML news sites. |
| `TavilyExtractor` | Tavily Extract API | 1 credit / 5 URLs | Fallback. Handles JS-rendered/paywalled content. |

**Post-MVP extractors**:
- `FirecrawlExtractor` — Self-hosted via `FIRECRAWL_URL`. Handles JS-rendered sites without Tavily credits.
- `Crawl4AIExtractor` — Deferred. Python-first, no official JS SDK, awkward async polling model.

### Stage 3: Research Tools

**Goal**: Let the Article Agent find additional information during deep-dive generation.

These are **Mastra tools** (not adapters). They wrap Stage 1/2 adapter instances to avoid duplicating fetch/extraction logic.

| Tool | Wraps | Purpose |
|------|-------|---------|
| `tavily-search` | Tavily Search API | Find more articles on a topic |
| `fetch-content` | `ContentExtractor` chain | Extract full text from a URL |
| `tavily-extract` | Tavily Extract API | Extract content from JS-heavy URLs |

---

## Adapter Interfaces

All adapter types live in `packages/shared/src/types.ts` for use across server and (future) tests.

### Types

```typescript
// ─── Pipeline Adapter Types ──────────────────────────────────

/** Article discovered by a Stage 1 source adapter */
export interface DiscoveredArticle {
  title: string;
  url: string;
  snippet: string | null;
  author: string | null;
  publishedAt: string | null;
  externalId: string | null;   // HN story ID, RSS guid, etc.
  score: number | null;        // HN score, null for RSS/Tavily
  sourceType: SourceType;
}

/** Content extracted by a Stage 2 extractor */
export interface ExtractedContent {
  title: string | null;        // May differ from RSS title
  content: string;             // Full article text (plain text, NOT markdown)
  author: string | null;
  publishedAt: string | null;
  siteName: string | null;     // e.g. "TechCrunch"
  excerpt: string | null;      // Short summary from the page
}
```

### SourceAdapter (Stage 1)

```typescript
export interface SourceAdapter {
  /** Which source type this adapter handles */
  readonly type: SourceType;

  /** Discover articles from a configured source */
  fetch(source: Source, options?: SourceFetchOptions): Promise<DiscoveredArticle[]>;
}

export interface SourceFetchOptions {
  /** Search queries (used by Tavily, ignored by RSS/HN) */
  queries?: string[];
  /** Max results to return (adapter-specific default if omitted) */
  maxResults?: number;
}
```

### ContentExtractor (Stage 2)

```typescript
export interface ContentExtractor {
  /** Human-readable name for logging */
  readonly name: string;

  /**
   * Extract article content from a URL.
   * Returns null if extraction fails (next extractor in chain is tried).
   */
  extract(url: string): Promise<ExtractedContent | null>;
}
```

**Why no `SearchProvider` interface for Stage 3?** Stage 3 tools are Mastra tools with `createTool()`, typed via `inputSchema`/`outputSchema`. They don't need a shared interface — they wrap adapter instances directly.

---

## Extraction Chain Behavior

The extraction chain is the critical path for content quality. Getting this wrong means empty articles or wasted API credits.

### Chain Order (MVP)

```
1. ReadabilityExtractor (always runs first — free, handles ~95% of news sites)
      │
      ├── Success → return ExtractedContent
      │
      └── Failure (returns null)
              │
              ├── TAVILY_API_KEY is set → try TavilyExtractor
              │       │
              │       ├── Success → return ExtractedContent
              │       │
              │       └── Failure → discard article (log warning)
              │
              └── TAVILY_API_KEY not set → discard article (log warning)
```

### Rules

1. **Readability always runs first**. It's free, fast, and handles most static HTML news sites.
2. **TavilyExtractor is a paid fallback only**. It is _never_ called when Readability succeeds.
3. **If all extractors fail, discard the article**. Log a warning with the URL and continue. Don't store articles without content — they provide no value to the headline or article agents.
4. **Chain order is fixed, not configurable**. Free/fast extractors always come before paid ones. Users can only enable/disable paid extractors via env vars.

### Post-MVP Chain

```
ReadabilityExtractor → FirecrawlExtractor (if FIRECRAWL_URL set) → TavilyExtractor (if TAVILY_API_KEY set)
```

Firecrawl slots between Readability and Tavily because it's self-hosted (no per-request cost once running), but heavier to set up than Readability.

---

## Adapter Registry

The registry builds adapter lists from configuration. Located at `apps/server/src/services/adapters/registry.ts`.

### Source Adapters

```typescript
/**
 * Build the list of active source adapters based on configuration.
 * Adapters are enabled by the presence of their required env vars.
 */
function buildSourceAdapters(config: AppConfig): SourceAdapter[] {
  const adapters: SourceAdapter[] = [
    new RssSourceAdapter(),          // Always present — RSS is free
    new HackerNewsSourceAdapter(),   // Always present — HN API is free
  ];

  if (config.tavilyApiKey) {
    adapters.push(new TavilySearchSourceAdapter(config.tavilyApiKey));
  }

  // Post-MVP: ExaSourceAdapter, GNewsSourceAdapter, etc.

  return adapters;
}
```

### Extractor Chain

```typescript
/**
 * Build the ordered extractor chain.
 * Chain tries extractors in order, returns first success.
 * Free/fast extractors come before paid ones.
 */
function buildExtractorChain(config: AppConfig): ContentExtractor[] {
  const chain: ContentExtractor[] = [
    new ReadabilityExtractor(),      // Always first — free, fast
  ];

  // Post-MVP: FirecrawlExtractor (if FIRECRAWL_URL set)

  if (config.tavilyApiKey) {
    chain.push(new TavilyExtractor(config.tavilyApiKey));
  }

  return chain;
}
```

### Orchestration

```typescript
/**
 * Try extractors in chain order. Return first success, null if all fail.
 */
async function extractContent(
  chain: ContentExtractor[],
  url: string,
  logger: Logger,
): Promise<ExtractedContent | null> {
  for (const extractor of chain) {
    try {
      const result = await extractor.extract(url);
      if (result) {
        logger.debug({ extractor: extractor.name, url }, 'Extraction succeeded');
        return result;
      }
    } catch (error) {
      logger.warn({ extractor: extractor.name, url, error }, 'Extractor failed');
    }
  }
  logger.warn({ url }, 'All extractors failed, discarding article');
  return null;
}
```

---

## Configuration Model

Each adapter has its own environment variable(s). No single `CRAWLER_URL` — different services have different APIs and auth mechanisms.

### Pipeline Environment Variables

| Variable | Required | Default | Used By |
|----------|----------|---------|---------|
| `TAVILY_API_KEY` | No | — | TavilySearchSourceAdapter, TavilyExtractor, tavily-search tool, tavily-extract tool |
| `FIRECRAWL_URL` | No | — | FirecrawlExtractor (post-MVP) |
| `EXA_API_KEY` | No | — | ExaSourceAdapter (post-MVP) |
| `GNEWS_API_KEY` | No | — | GNewsSourceAdapter (post-MVP) |
| `SERPER_API_KEY` | No | — | SerperSourceAdapter (post-MVP) |
| `PERPLEXITY_API_KEY` | No | — | Perplexity research tool (post-MVP, Stage 3 only) |

**Note**: `TAVILY_API_KEY` is the only pipeline env var needed for MVP. All others are post-MVP.

### Adapter Activation Rules

- **Always active**: RssSourceAdapter, HackerNewsSourceAdapter, ReadabilityExtractor
- **Active if env var set**: TavilySearchSourceAdapter, TavilyExtractor
- **Post-MVP**: All others

---

## Data Flow

### Daily Ingestion (Cron)

```
06:00 Cron Trigger
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│  1. SOURCE DISCOVERY (parallel)                          │
│  ├── RssSourceAdapter.fetch() for each enabled source   │
│  ├── HackerNewsSourceAdapter.fetch()                    │
│  └── TavilySearchSourceAdapter.fetch() per search query │
│                                                          │
│  All return DiscoveredArticle[]                          │
└──────────────────────┬──────────────────────────────────┘
                       │ merged DiscoveredArticle[]
                       ▼
┌─────────────────────────────────────────────────────────┐
│  2. DEDUPLICATION                                        │
│  ├── URL normalization (strip utm_*, ref, fbclid, etc.) │
│  ├── Title similarity (Dice coefficient > 0.7)          │
│  └── Filter already-seen articles (last 48h in DB)      │
└──────────────────────┬──────────────────────────────────┘
                       │ unique DiscoveredArticle[]
                       ▼
┌─────────────────────────────────────────────────────────┐
│  3. CONTENT EXTRACTION (parallel, for snippet-only)     │
│  ├── extractContent(chain, url) per article             │
│  │   └── ReadabilityExtractor → TavilyExtractor         │
│  └── Articles where all extractors fail → discarded     │
└──────────────────────┬──────────────────────────────────┘
                       │ articles with ExtractedContent
                       ▼
┌─────────────────────────────────────────────────────────┐
│  4. STORE raw_articles in SQLite                         │
│  └── DiscoveredArticle + ExtractedContent → raw_articles │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  5. HEADLINE AGENT (Mastra, structured output)           │
│  ├── Groups articles by topic/story                     │
│  ├── Assigns relevance scores per user interests        │
│  ├── Generates personalized headline + summary          │
│  └── Assigns tags + topicType (hot/normal/standalone)   │
└──────────────────────┬──────────────────────────────────┘
                       │ daily topics
                       ▼
┌─────────────────────────────────────────────────────────┐
│  6. STORE daily_topics + links to raw_articles           │
└─────────────────────────────────────────────────────────┘
```

### Article Deep-Dive (On-Demand)

```
User clicks headline
       │
       ▼
┌──────────────────────────────────────────┐
│  Check cache (generated_articles table)   │
│  ├── Hit → return cached markdown        │
│  └── Miss → generate                    │
└──────────────────┬───────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│  Article Agent (Mastra, streaming)                        │
│  ├── Input: topic, source articles, user preferences     │
│  ├── Tools available (Stage 3):                          │
│  │   ├── tavily-search → find more articles on topic     │
│  │   ├── fetch-content → extract full text (uses chain)  │
│  │   └── tavily-extract → get JS-heavy page content      │
│  ├── Generates comprehensive article in markdown         │
│  └── Streams tokens to client via SSE                    │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────┐
│  Cache generated article in SQLite        │
└──────────────────────────────────────────┘
```

---

## Adapter File Structure

```
apps/server/src/services/
├── adapters/
│   ├── source/
│   │   ├── rss.ts              # RssSourceAdapter
│   │   ├── hackernews.ts       # HackerNewsSourceAdapter
│   │   └── tavily-search.ts    # TavilySearchSourceAdapter
│   ├── extractor/
│   │   ├── readability.ts      # ReadabilityExtractor
│   │   └── tavily-extract.ts   # TavilyExtractor
│   └── registry.ts             # buildSourceAdapters, buildExtractorChain, extractContent
├── ingestion.ts                # Orchestrator: fetch → dedup → extract → store
├── dedup.ts                    # URL normalization + title similarity
└── cron.ts                     # Cron scheduling
```

---

## Researcher Comparison

Analysis of an external research document's recommendations vs our spec decisions.

| Researcher Claim | Assessment | Our Decision |
|---|---|---|
| 3-category model (Search / Extraction / SERP) | Good start, but maps poorly to data flow. "SERP Infra" is just another discovery adapter. | Refined 3-stage model: Discovery → Extraction → Research Tools |
| Readability + linkedom primary extraction | Correct, matches our ADR-007 | Keep as-is |
| Add `turndown` (HTML→Markdown) | Unnecessary — Readability returns `textContent` (plain text). LLM processes text, not markdown. | Skip turndown |
| `feedparser` for RSS | Wrong package. We chose `@extractus/feed-extractor` (Bun support, ESM, maintained). | Keep our choice |
| Tier 2: Browserless/Chrome sidecar | Overkill for news sites. Adds Docker complexity. News sites are static HTML. | Skip for MVP and likely post-MVP |
| Tier 3: single `CRAWLER_URL` env var | Too simplistic — different APIs need different auth/config. | Per-adapter env vars |
| Firecrawl self-host not recommended | Correct for news — high ops, no quality gain over Readability | Aligns with post-MVP deferral |
| Redis cache 24h TTL | Doesn't fit single-container SQLite. Content stored in `raw_articles.content`. | SQLite IS the cache |
| Perplexity as search alternative | Imprecise — Perplexity returns synthesized answers, not raw URLs. Answer engine, not search API. | Stage 3 research tool only, not Stage 1 discovery |
| Exa as search alternative | Valid — neural/embedding search, returns actual URLs | Post-MVP SourceAdapter |
| Readability F1 ~0.93 vs Trafilatura ~0.94 | Tied. Trafilatura is Python-only. Not worth adding Python to Bun container. | Keep Readability |

**Where our spec is better**: ContentExtractor interface, specific researched deps, cost budget, Mastra pipeline integration, Tavily dual-use (search + extract fallback).

---

## Extension Guide

### Adding a New Source Adapter

1. Create `apps/server/src/services/adapters/source/<name>.ts`
2. Implement `SourceAdapter` interface:
   ```typescript
   import type { DiscoveredArticle, Source, SourceAdapter, SourceFetchOptions } from '@open-news/shared';

   export class MySourceAdapter implements SourceAdapter {
     readonly type = 'my-source' as const; // Add to SOURCE_TYPES first

     async fetch(source: Source, options?: SourceFetchOptions): Promise<DiscoveredArticle[]> {
       // Fetch articles, return normalized DiscoveredArticle[]
     }
   }
   ```
3. Add the source type to `SOURCE_TYPES` in `packages/shared/src/types.ts`
4. Add env var (if needed) and register in `buildSourceAdapters()` in `registry.ts`
5. Add env var documentation to `docs/SPEC.md` section 8

### Adding a New Content Extractor

1. Create `apps/server/src/services/adapters/extractor/<name>.ts`
2. Implement `ContentExtractor` interface:
   ```typescript
   import type { ContentExtractor, ExtractedContent } from '@open-news/shared';

   export class MyExtractor implements ContentExtractor {
     readonly name = 'my-extractor';

     async extract(url: string): Promise<ExtractedContent | null> {
       // Extract content, return null on failure
     }
   }
   ```
3. Add to `buildExtractorChain()` in `registry.ts` — respect chain order (free before paid)
4. Add env var documentation to `docs/SPEC.md` section 8

### Adding a New Research Tool (Stage 3)

1. Create `apps/server/src/mastra/tools/<name>.ts`
2. Use `createTool` from `@mastra/core/tools` with typed `inputSchema`/`outputSchema`
3. Prefer wrapping an existing adapter instance over duplicating fetch logic
4. Register the tool in the Article Agent's `tools` map
