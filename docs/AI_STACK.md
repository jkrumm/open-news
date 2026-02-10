# OpenNews - AI Stack & Pipeline Architecture

> Core AI architecture: agents, prompts, compression, streaming, tool matrix, MVP scope, and roadmap.
> For adapter interfaces, data flow, and extension guide, see [`PIPELINE.md`](./PIPELINE.md).
> For system architecture, API design, and infrastructure, see [`ARCHITECTURE.md`](./ARCHITECTURE.md).

---

## 1. The Complete Pipeline

### Daily Digest (Cron, 6am)

```
Step 1: DISCOVER        Step 2: DEDUP           Step 3: EXTRACT
(parallel adapters)     (URL + title)           (chain, parallel)

RSS feeds ──┐                                   Readability ──┐
HN API ─────┤──→ DiscoveredArticle[] ──→ unique articles ──→  │──→ raw_articles
Tavily ─────┘    (merged, flat)          (normalized URLs,    │    (with content)
                                          Dice title >0.7)    Tavily Extract ─┘
                                                              (fallback only)

Step 4: GROUP + SCORE              Step 5: STORE
(Headline Agent, structured)       (SQLite)

raw_articles ──→ AI generateObject() ──→ daily_topics
                 - cluster by story       + topic_sources
                 - score per user          + topic_tags
                 - headline + summary
                 - tags + topicType
```

### On-Demand Article Generation (User clicks topic)

```
Step A: GATHER                Step B: COMPRESS              Step C: SYNTHESIZE
(Mastra agent + tools)        (per-source, structured)      (streaming to client)

topic sources ──┐
tavily-search ──┤──→ sources[] ──→ generateObject() ──→ CompressedSource[] ──→ agent.stream()
fetch-content ──┘    (full text)   per source:              (combined context)    ──→ SSE
                                   - key facts verbatim                           ──→ useCompletion
                                   - citations [1][2]                             ──→ streamdown
                                   - metrics/quotes
```

**Post-MVP addition**: Step D (Critique) — separate LLM reviews synthesis, max 1 revision.

---

## 2. Core AI Stack

### What We Use and Why

| Layer | Tool | Role | Why This One |
|-------|------|------|-------------|
| **Orchestration** | Mastra v1 (`@mastra/core`) | Agent + workflow + tool framework | Built on AI SDK, Zod-native, streaming built-in |
| **LLM Abstraction** | Vercel AI SDK (`ai`) | Provider switching, generateObject, streamText | Provider-agnostic, Zod structured output, SSE protocol |
| **Model Providers** | `@ai-sdk/google`, `@ai-sdk/openai`, `@ai-sdk/anthropic` | Plug any LLM | ENV-configured, no code changes to switch |
| **Structured Output** | Zod + `generateObject()` | Type-safe LLM responses | Eliminates string parsing, retry on malformed output |
| **Streaming** | `agent.stream()` → `toDataStreamResponse()` → `useCompletion()` → `streamdown` | Token-by-token article rendering | Purpose-built chain, no custom protocol needed |

### When to Use Mastra vs AI SDK Directly

| Task | Use | API | Why |
|------|-----|-----|-----|
| Topic grouping / scoring | AI SDK directly | `generateObject({ model, schema, prompt })` | One-shot, no tools, structured output |
| Headline generation | AI SDK directly | `generateObject()` | Same — simple classification task |
| Article generation | Mastra Agent | `agent.stream()` | Multi-step: needs tools (search, fetch), streaming |
| Compression per source | AI SDK directly | `generateObject()` | One-shot extraction, Zod schema per source |
| Critique loop (post-MVP) | AI SDK directly | `generateObject()` | One-shot evaluation, scored rubric |

**Rule of thumb**: If the LLM call needs tools or streaming, use a Mastra Agent. If it's a one-shot structured output call, use AI SDK `generateObject()` directly.

### Model Strategy

**MVP**: Single model via ENV (`LLM_PROVIDER` + `LLM_MODEL`). Default: `google/gemini-2.0-flash`.

**Post-MVP P1**: Two-tier routing:
- `LLM_MODEL_FAST` — classification, compression, grouping (cheap, fast)
- `LLM_MODEL_PRO` — article synthesis, critique (quality matters)

**Post-MVP P2**: Three-tier (add `LLM_MODEL_STRATEGIC` for complex multi-step research).

---

## 3. Pipeline Stage Details

### Stage 1: Source Discovery

**MVP Adapters** (all free or free-tier):

| Adapter | Source | Cost | What It Gets Us |
|---------|--------|------|----------------|
| `RssSourceAdapter` | User's RSS/Atom feeds | Free | Backbone — user controls their sources |
| `HackerNewsSourceAdapter` | HN Firebase API (top 50) | Free | Tech community signal, score = quality proxy |
| `TavilySearchSourceAdapter` | Tavily Search API | Free tier (1K/mo) | Topic-based discovery RSS misses |

**How they work together**: RSS gives curated feeds the user chose. HN gives trending tech. Tavily fills gaps by searching user's `searchQueries[]` from settings. All run in parallel, results merged into flat `DiscoveredArticle[]`.

**Post-MVP Source Adapters**:

| Adapter | Why Add It | Tier |
|---------|-----------|------|
| `ExaSourceAdapter` | Neural/embedding search, semantic complement to Tavily | P1 |
| `RedditSourceAdapter` | Subreddit monitoring (r/programming, r/technology, custom) | P1 |
| `GNewsSourceAdapter` | Mainstream news coverage (100 req/day free) | P2 |
| `SerperSourceAdapter` | Google SERP results for broad coverage | P2 |

**NOT a Source Adapter**: Perplexity (returns synthesized answers, not URLs → Stage 3 research tool only).

### Stage 2: Deduplication & Ranking

**Three-tier dedup** (validated by SearXNG + FreshRSS patterns):

```
Tier 1: URL Normalization (O(1) hash lookup)
  - Strip: utm_*, fbclid, gclid, ref, source, medium, campaign
  - Normalize: remove www, trailing slash, lowercase host
  - Hash normalized URL → check against last 48h in DB

Tier 2: Title Similarity (O(n²) but only for non-deduped, <500 articles/day)
  - Dice coefficient (fast-dice-coefficient) > 0.7 = same story
  - Also check: same author + similar publish time = likely dupe

Tier 3: Skip (no semantic embeddings MVP — Dice + URL is sufficient for <500/day)
```

**Ranking** (inspired by SearXNG's position×weight scoring):

```typescript
// Multi-source accumulation: article found in multiple sources gets boosted
score = sum_per_source(1 / (position + 1) * adapterWeight)
// adapterWeight: RSS=1.0, HN=1.2 (curated), Tavily=0.8 (noisy)

// Recency decay (optional, post-MVP):
score *= Math.exp(-(hoursSincePublished / halfLifeHours))
```

**Merge strategy**: When same article found via multiple sources, keep longest extraction, preserve all source URLs.

### Stage 3: Content Extraction

**MVP Chain** (free-first, fallback to paid):

```
ReadabilityExtractor (always first — free, ~95% success on news sites)
  ├── Success → ExtractedContent
  └── Failure → TavilyExtractor (if TAVILY_API_KEY set)
        ├── Success → ExtractedContent
        └── Failure → discard (log warning)
```

**Validation rules** (from GPT Researcher pattern):
- Minimum 100 characters content (discard empty extractions)
- Must have non-empty title
- Log extraction success/failure rates per adapter

**Post-MVP Chain**:

```
Readability → Firecrawl (if FIRECRAWL_URL, self-hosted, no per-request cost) → Tavily Extract
```

### Stage 4: Headline Agent (Topic Grouping + Scoring)

**This is the key daily AI step.** Uses AI SDK `generateObject()` directly (no Mastra agent needed — one-shot, no tools).

**Input**: All day's `raw_articles[]` + user `settings` (interests, topics, searchQueries)

**Output** (Zod schema):

```typescript
z.object({
  topics: z.array(z.object({
    headline: z.string(),           // Personalized, engaging headline
    summary: z.string(),            // 2-3 sentences
    topicType: z.enum(['hot', 'normal', 'standalone']),
    relevanceScore: z.number(),     // 0-1, based on user interests
    tags: z.array(z.string()),      // From existing tags or suggest new
    articleIndices: z.array(z.number()), // Which raw_articles belong to this topic
  })),
  discarded: z.array(z.number()),   // Indices of irrelevant articles (score < 0.3)
})
```

**Prompt strategy**:
- Role: "You are an expert news editor curating a personalized daily digest"
- Inject user interests, topics, background
- Group articles about the same story/event together
- Score relevance to THIS user's interests (not general interest)
- Discard articles below 0.3 relevance threshold

### Stage 5: Article Agent (On-Demand Deep-Dive)

**This is the crown jewel.** Uses Mastra Agent with tools + streaming.

**Architecture**: Three-phase generation (Gather → Compress → Synthesize)

#### Phase A — Gather (Mastra agent calls tools)

- Start with topic's source articles from `topic_sources`
- Agent can optionally call `tavily-search` for supplementary sources
- Agent can call `fetch-content` to extract full text from URLs
- Result: Array of `{ url, title, content, publishedAt }`

#### Phase B — Compress (deterministic pre-processing, NOT agent-driven)

Compression is a batch of independent `generateObject()` calls — no tool use, no reasoning needed. Each source is compressed independently before the agent synthesizes.

- Extract key facts, quotes, metrics — VERBATIM (never paraphrase)
- Assign citation numbers `[1]`, `[2]`, `[3]`
- Result: `CompressedSource[]` with facts and citation numbers

```typescript
const compressedSourceSchema = z.object({
  sourceIndex: z.number(),
  facts: z.array(z.object({
    text: z.string(),        // Verbatim fact or quote
    citations: z.array(z.number()), // Which source(s)
  })),
  keyMetrics: z.array(z.string()), // Numbers, dates, stats
})
```

#### Phase C — Synthesize (Mastra agent streaming)

- Combine compressed sources into coherent article
- Inject user context (expertise level, preferred tone, language)
- Citation mandate: "Every factual claim MUST cite [N]"
- Stream via `toDataStreamResponse()` → `useCompletion()` → `streamdown`

**Prompt principles** (validated by 2026 research + all competitors):

```
1. Role: "You are a senior tech journalist writing for a reader with {expertiseLevel} knowledge"
2. Citation: "Every factual claim MUST include [N] citation. No exceptions."
3. Anti-hallucination: "ONLY use information from provided sources. If uncertain, say so."
4. Structure: "Use ## headings. Structure as best fits content. Be thorough."
5. Tone: "Conversational but authoritative. No corporate jargon. No AI self-reference."
6. Readability: "Active voice, varied sentence lengths, short paragraphs (3-4 sentences)"
```

**Token overflow handling** (from Open Deep Research):
- If synthesis exceeds model context, truncate compressed sources by 10%
- Retry up to 3 times
- Last resort: reduce source count

---

## 4. Tool & Library Matrix

### MVP Tools (What We Ship With)

| Purpose | Tool/Library | Type | Cost | Self-Hostable |
|---------|-------------|------|------|---------------|
| RSS parsing | `@extractus/feed-extractor` | JS library | Free | N/A (library) |
| HN API | Firebase REST API | HTTP | Free | N/A (public API) |
| Web search | Tavily Search API | API key | Free tier 1K/mo | No |
| Content extraction (primary) | `@mozilla/readability` + `linkedom` | JS library | Free | N/A (library) |
| Content extraction (fallback) | Tavily Extract API | API key | 1 credit/5 URLs | No |
| Title similarity | `fast-dice-coefficient` | JS library | Free | N/A (library) |
| AI orchestration | `@mastra/core` v1 | JS library | Free | N/A (library) |
| LLM abstraction | Vercel AI SDK (`ai`) | JS library | Free | N/A (library) |
| LLM provider | User's choice (Google/OpenAI/Anthropic) | API key | Varies | Some (Ollama) |
| Cron scheduling | `croner` | JS library | Free | N/A (library) |
| Markdown streaming | `streamdown` | JS library | Free | N/A (library) |
| Database | SQLite via `bun:sqlite` + Drizzle | Built-in | Free | N/A (embedded) |

**MVP external dependencies requiring API keys**:
1. LLM provider (required) — Google Gemini has generous free tier
2. Tavily (optional) — enhances discovery + extraction fallback, free tier sufficient

### Post-MVP Tools

| Purpose | Tool | When | Cost | Why Add It |
|---------|------|------|------|-----------|
| Neural search | Exa API | P1 | Free tier | Semantic discovery complement |
| Reddit monitoring | Reddit API | P1 | Free | Community signals |
| JS-rendered extraction | Firecrawl (self-hosted) | P1 | Free (self-hosted) | Handles SPAs without Tavily credits |
| Research answers | Perplexity API | P2 | Paid | Deep-dive supplementary research |
| Google SERP | Serper API | P2 | Free tier | Broad news coverage |
| Mainstream news | GNews API | P2 | Free (100/day) | Non-tech news |

---

## 5. MVP Scope — What's In, What's Out

### IN (MVP)

| Feature | Implementation | Effort |
|---------|---------------|--------|
| RSS + HN + Tavily source adapters | `SourceAdapter` interface, parallel fetch | Medium |
| Readability + Tavily extraction chain | `ContentExtractor` interface, chain fallback | Medium |
| URL normalization + Dice dedup | Strip tracking params, title similarity | Low |
| Multi-source score accumulation | Position × weight scoring | Low |
| Headline Agent (topic grouping) | AI SDK `generateObject()`, Zod schema | Medium |
| Article Agent (deep-dive synthesis) | Mastra agent with tools, streaming | High |
| Progressive compression pipeline | Compress per-source → synthesize | Medium |
| Inline `[N]` citations | Prompt enforcement, sources section | Medium |
| Token overflow retry | Truncate 10%, retry 3x | Low |
| Streaming to frontend | `toDataStreamResponse()` → `useCompletion()` → `streamdown` | Medium |
| Single model via ENV | `LLM_PROVIDER` + `LLM_MODEL` | Low |
| Daily cron (6am) | `croner` scheduler | Low |

### OUT (Post-MVP)

| Feature | Why Defer | Priority |
|---------|----------|----------|
| Critique/refinement loop | Single-pass is good enough for launch | P1 |
| Classification-first filtering | Optimization — extract first, filter later for MVP | P1 |
| Pipeline progress SSE events | Nice UX but not blocking | P1 |
| User preference injection (tone/depth) | Default settings sufficient for MVP | P1 |
| Two output modes (summary vs deep-dive) | One mode (deep-dive) is enough | P1 |
| Per-adapter config UI (weight, timeout) | ENV config sufficient | P1 |
| Saved searches / query subscriptions | Settings searchQueries[] covers this | P1 |
| Multi-tier LLM routing | Single model works, optimize later | P2 |
| Firecrawl / Exa / Reddit adapters | More sources = better, but RSS+HN+Tavily is enough | P1-P2 |
| Archiving / retention limits | SQLite handles months of data fine | P2 |
| Google Reader API compatibility | Mobile app support, big effort | P2 |

---

## 6. Core Workflows (Mastra Implementation)

### Workflow 1: Daily Digest

**Not a Mastra workflow** — it's a plain async function called by cron. No agent needed for orchestration; each step is deterministic except the Headline Agent call. A plain async function is simpler for deterministic steps with no tool use or agent reasoning.

```
cronJob('0 6 * * *') → digestService.run()
  1. fetchAllSources(adapters)     // parallel Promise.all
  2. deduplicateArticles(articles)  // URL + Dice
  3. extractContent(chain, urls)    // parallel, chain fallback
  4. storeRawArticles(db, articles) // Drizzle insert
  5. generateHeadlines(articles, settings)  // AI SDK generateObject()
  6. storeTopics(db, topics)        // Drizzle insert with relations
```

### Workflow 2: Article Generation (Mastra Agent)

**This IS a Mastra agent** — it needs tools and streaming.

```typescript
// Agent definition
const articleAgent = new Agent({
  name: 'article-agent',
  model: getLlmModel(config),  // provider-agnostic via AI SDK
  instructions: articleSystemPrompt,
  tools: {
    'tavily-search': tavilySearchTool,
    'fetch-content': fetchContentTool,
    'tavily-extract': tavilyExtractTool,
  },
});

// Route handler
app.post('/api/v1/article/:topicId/generate', async (c) => {
  const topic = await getTopicWithSources(topicId);
  const settings = await getSettings();

  // Phase B: Compress sources (parallel generateObject calls)
  const compressed = await Promise.all(
    topic.sources.map(source => compressSource(source))
  );

  // Phase C: Synthesize (streaming)
  const stream = await articleAgent.stream(
    buildSynthesisPrompt(topic, compressed, settings)
  );

  return stream.toDataStreamResponse();
});
```

**Why the agent doesn't do compression**: Compression is a batch of independent `generateObject()` calls — no tool use, no reasoning needed. The agent handles synthesis + optional tool calls for additional research.

---

## 7. Key Decisions Validated by Research

| Decision | Validated By | Confidence |
|----------|-------------|------------|
| Readability + linkedom for extraction | GPT Researcher (7 scrapers, Readability still primary), all competitors | High |
| Provider-agnostic via AI SDK | Open Deep Research (multi-model), GPT Newspaper (locked to OpenAI = bad) | High |
| SQLite for everything (no Redis, no vector DB) | FreshRSS (10+ years at scale), Perplexica | High |
| Dice coefficient for dedup | No competitor does semantic title dedup — we're ahead | High |
| Progressive compression before synthesis | Open Deep Research (verbatim preservation), DeerFlow (context compression) | High |
| Inline [N] citations | Perplexica (every sentence), 2026 best practices | High |
| Single Docker container | FreshRSS (proven self-hosted pattern) | High |
| Adapter interfaces (minimal contract) | SearXNG (221 engines with simple request/response) | High |
| Streaming via useCompletion + streamdown | Purpose-built for one-shot AI streaming | High |
| No turndown (HTML→Markdown) | Readability returns textContent, LLM processes text not markdown | High |
| No Browserless/Chrome sidecar | News sites are static HTML, Tavily fallback handles JS | High |
| Headline Agent as single generateObject() | No pre-clustering needed — LLM handles grouping+scoring in one pass | High |
| Compression as deterministic pre-processing | Not agent-driven — batch of independent structured output calls | High |
