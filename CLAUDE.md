# OpenNews

AI-powered news aggregator. Single Docker container, provider-agnostic LLM, self-hosted. Bun monorepo with Hono backend (Mastra AI library) + React SPA (Vite).

## Specification

- `docs/SPEC.md` — Full technical spec (PRD, ADRs, schema, API design, infra). Read on demand when implementing tasks.
- `docs/PIPELINE.md` — Pipeline architecture: 3-stage model, adapter interfaces, extraction chain, registry, extension guide.
- `docs/IMPLEMENTATION.md` — 28 tasks across 5 phases with task-level dependencies

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
| Frontend | React 19, Vite, TanStack Router, TanStack Query |
| Styling | Tailwind v4 (CSS-first), ShadCN/ui + BasaltUI |
| Streaming | `useCompletion` (AI SDK) + `streamdown` (markdown renderer) |
| Logging | Pino + hono-pino + Logdy (dev browser UI) |
| Auth | Shared secret → JWT cookie (SPA) + Bearer AUTH_SECRET (API) |
| CI | Biome check + tsc -b + commitlint |

## Critical Architecture Decisions

These are the most mistake-prone rules. Violating any of these will cause build or runtime failures.

1. **Mastra as library** — import from `@mastra/core` subpaths (`/mastra`, `/agent`, `/tools`, `/workflows`), NOT from `@mastra/core` root. No `mastra build`, no Mastra CLI.
2. **Mastra v1 API** — `createWorkflow`/`createStep` + `.then().commit()`, NOT legacy `new Workflow`/`new Step`. Tools use `execute(inputData)` NOT `execute({ context })`.
3. **Streaming** — `useCompletion` (one-shot), NOT `useChat` (multi-turn). Server: `agent.stream()` + `toDataStreamResponse()`.
4. **RSS** — `@extractus/feed-extractor`, NOT `rss-parser` (stale, CJS-only).
5. **DOM** — `linkedom` (`parseHTML`), NOT `jsdom` (90% smaller, 3x faster).
6. **String similarity** — `fast-dice-coefficient`, NOT `string-similarity` (abandoned 5+ years).
7. **Markdown** — `streamdown`, NOT `react-markdown` (AI-streaming optimized, built-in GFM).
8. **Tailwind v4** — CSS-first config (`@import "tailwindcss"`), NO `tailwind.config.js` file.
9. **SQLite driver** — `bun:sqlite` (built-in), NOT `better-sqlite3`. WAL mode + pragmas at connection init.
10. **Auth** — JWT signed with key derived from `AUTH_SECRET` (deterministic, survives restarts). No expiry. Bearer compares raw `AUTH_SECRET` directly.
11. **LLM config** — ENV-only for MVP. Settings UI override is post-MVP P1.
12. **Exports** — Named exports only, no default exports. Function components, no `React.FC`.
13. **Routing** — TanStack Router file-based routing. Vite plugin `tanstackRouter()` MUST come before `react()` in plugins array. Routes use `createFileRoute`, params are type-safe (e.g., `/article/$topicId`).
14. **Pipeline adapters** — `SourceAdapter` + `ContentExtractor` are the core interfaces. Types live in `packages/shared`, implementations in `apps/server/src/services/adapters/`. See `docs/PIPELINE.md`.
15. **Adapter file structure** — `services/adapters/source/` (Stage 1), `services/adapters/extractor/` (Stage 2), `services/adapters/registry.ts` (builder functions).
16. **Mastra tools wrap adapters** — Stage 3 research tools are thin wrappers around Stage 1/2 adapter instances. No duplicated fetch/extraction logic.

## Monorepo Structure

```
apps/server/     # Hono backend + Mastra agents/workflows/tools + Drizzle
apps/web/        # React SPA (Vite) + TanStack Query + streamdown
packages/shared/ # Domain types, Zod schemas, Pino logger factory
```

## Commands

```bash
bun run dev              # Start all (server + web)
bun run dev:server       # Server only (bun --hot)
bun run dev:web          # Vite dev server only
bun run check            # Biome check (format + lint)
bun run check:fix        # Biome check --write
bun run typecheck        # tsc -b (project references)
bun run db:generate      # Drizzle: generate migration
bun run db:migrate       # Drizzle: apply migrations
bun run db:studio        # Drizzle: browser studio
```

## Skills

Inherited from SourceRoot: `/commit`, `/pr`, `/release`, `/fix-sentry`, `/upgrade-deps`, `/code-quality`, `/research`, `/review`

| Skill | Purpose | Context |
|-------|---------|---------|
| `/docs` | Sync docs (SPEC, IMPL, CLAUDE, README) with code changes | main |
| `/mastra` | Mastra v1 API patterns and examples | fork |
| `/hono` | Hono framework patterns | fork |
| `/tanstack-query` | TanStack Query patterns | fork |
| `/react` | React best practices (inherited from SourceRoot) | fork |
| `/web-design` | Web design guidelines (inherited from SourceRoot) | fork |

## Implementation Workflow

1. Pick next unblocked task from `docs/IMPLEMENTATION.md`
2. `/research` if touching unfamiliar libraries
3. Implement (read existing code first, build on patterns)
4. `/docs` — sync any spec/doc drift from implementation
5. `/code-quality` → `/commit`

## No AI Attribution

No `Co-Authored-By`, no "Generated with Claude Code", no AI disclaimers anywhere.
