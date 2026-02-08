# OpenNews

Personal AI-powered news aggregator. Self-hosted, provider-agnostic LLM, single Docker container deployment.

## Overview

OpenNews is a minimalist news aggregator that uses AI to:
- Fetch articles from RSS feeds, Hacker News, and web search
- Extract and clean article content
- Deduplicate similar articles
- Summarize articles on demand
- Generate smart recaps across multiple articles

Built as a single-user, self-hosted application with emphasis on privacy, simplicity, and LLM provider flexibility.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Runtime | Bun (monorepo workspaces) |
| Server | Hono + hono-pino |
| AI | Mastra v1 (`@mastra/core`) as library, Vercel AI SDK |
| LLM | Provider-agnostic (Google/OpenAI/Anthropic/compatible) |
| Database | SQLite via `bun:sqlite` + Drizzle ORM (WAL mode) |
| Sources | RSS (`@extractus/feed-extractor`) + HN API + Tavily search |
| Content extraction | `@mozilla/readability` + `linkedom`, Tavily fallback |
| Dedup | URL normalization + `fast-dice-coefficient` (Dice similarity) |
| Cron | croner (ESM, Bun-compatible, timezone-aware) |
| Frontend | React 19, Vite, react-router-dom 7, TanStack Query |
| Styling | Tailwind v4 (CSS-first), ShadCN/ui + BasaltUI |
| Streaming | `useCompletion` (AI SDK) + `streamdown` (markdown renderer) |
| Logging | Pino + hono-pino + Logdy (dev browser UI) |
| Auth | Shared secret → JWT cookie (SPA) + Bearer AUTH_SECRET (API) |

## Project Structure

```
open-news/
├── apps/
│   ├── server/          # Hono backend + Mastra agents/workflows/tools
│   └── web/             # React SPA (Vite) + TanStack Query
├── packages/
│   └── shared/          # Domain types, Zod schemas, Pino logger
├── docs/
│   ├── SPEC.md          # Full technical specification (PRD, ADRs, API design)
│   └── IMPLEMENTATION.md # 28 tasks across 5 phases
├── scripts/
│   ├── ralph-mvp.sh     # One-shot autonomous implementation script
│   └── ralph-status.sh  # Progress monitoring
└── CLAUDE.md            # AI assistant instructions
```

## Development

### Prerequisites

- [Bun](https://bun.sh) v1.0+
- (Optional) [Logdy](https://logdy.dev) for log streaming UI

### Setup

```bash
# Install dependencies
bun install

# Set up environment variables
cp .env.example .env
# Edit .env with your LLM provider credentials

# Generate database schema
bun run db:generate

# Apply migrations
bun run db:migrate
```

### Commands

```bash
# Development
bun run dev              # Start all (server + web)
bun run dev:server       # Server only (bun --hot)
bun run dev:web          # Vite dev server only

# Database
bun run db:generate      # Drizzle: generate migration
bun run db:migrate       # Drizzle: apply migrations
bun run db:studio        # Drizzle: browser studio

# Validation
bun run check            # Biome check (format + lint)
bun run check:fix        # Biome check --write
bun run typecheck        # tsc -b (project references)
```

### RALPH MVP Implementation Script

For initial implementation, use the RALPH (Reasoning And Learning Planning Helper) loop script:

```bash
# Start autonomous implementation
./scripts/ralph-mvp.sh

# Monitor progress
./scripts/ralph-status.sh

# Resume from interruption
./scripts/ralph-mvp.sh --resume
```

The script:
- Implements all 28 tasks from `docs/IMPLEMENTATION.md`
- Runs autonomously within each of 5 phases
- Pauses for human review after each phase
- Creates atomic commits per task
- Logs all activity to `.ralph-logs/`

See [scripts/README.md](scripts/README.md) for details.

## Documentation

| File | Purpose |
|------|---------|
| [docs/SPEC.md](docs/SPEC.md) | Full technical specification (PRD, ADRs, schema, API design, infra) |
| [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | 28 tasks across 5 phases with dependencies |
| [CLAUDE.md](CLAUDE.md) | AI assistant instructions and critical architecture decisions |
| [scripts/README.md](scripts/README.md) | RALPH automation script documentation |

## Architecture Highlights

### Mastra as Library

OpenNews uses Mastra v1 as a library (NOT `mastra build`). Import from subpaths:

```typescript
import { Mastra } from '@mastra/core';
import { Agent } from '@mastra/core/agent';
import { createTool } from '@mastra/core/tools';
import { createWorkflow, createStep } from '@mastra/core/workflows';
```

### Provider-Agnostic LLM

LLM configuration via environment variables (MVP):

```bash
LLM_PROVIDER=google  # google | openai | anthropic | compatible
LLM_API_KEY=...
LLM_MODEL=gemini-2.0-flash-exp
LLM_BASE_URL=...     # For compatible providers
```

Post-MVP: Settings UI override.

### Authentication

- **SPA**: Shared secret (`AUTH_SECRET`) → JWT cookie (no expiry, deterministic key)
- **External APIs**: Bearer token (raw `AUTH_SECRET`) for Glance/Obsidian plugins

### Deduplication Strategy

1. **URL normalization**: Strip trackers, normalize domains
2. **Title similarity**: Dice coefficient (`fast-dice-coefficient`) > 0.7 threshold
3. **Merge logic**: Keep oldest article, increment `duplicate_count`

### Content Extraction

1. **Primary**: `@mozilla/readability` + `linkedom` (lightweight DOM)
2. **Fallback**: Tavily extract API (premium tier)

## Deployment

(Post-MVP)

Single Docker container:
- Multi-stage build (bun install → bun build → production image)
- SQLite volume mount
- ENV-based configuration
- Health checks

## License

MIT

## Author

Johannes Krumm
