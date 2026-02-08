# OpenNews Web

React 19 SPA with Vite, TanStack Query, Tailwind v4, and AI SDK streaming.

## Stack

- **Framework**: React 19 + TanStack Router (file-based, type-safe)
- **Build**: Vite (with `@vitejs/plugin-react`)
- **State**: TanStack Query v5 (server state), React state (local UI)
- **Styling**: Tailwind v4 (CSS-first) + ShadCN/ui + BasaltUI theme
- **Streaming**: `useCompletion` from `@ai-sdk/react` + `streamdown` for markdown
- **Icons**: lucide-react

## Directory Structure

```
src/
├── main.tsx            # React entry point
├── routes/             # File-based routing (TanStack Router)
│   ├── __root.tsx      # Root layout with Outlet
│   ├── index.tsx       # Feed page (`/`)
│   ├── article.$topicId.tsx  # Article page (`/article/$topicId`)
│   ├── settings.tsx    # Settings page (`/settings`)
│   └── login.tsx       # Login page (`/login`)
├── components/
│   ├── TopicCard.tsx   # Headline card (summary, tags, source count)
│   ├── DaySection.tsx  # Date header + topic cards
│   ├── TagFilter.tsx   # Clickable tag pills
│   ├── ArticleView.tsx # Streaming markdown renderer (streamdown)
│   ├── SourceChip.tsx  # Source attribution
│   └── SettingsForm.tsx
├── hooks/
│   ├── use-feed.ts     # useInfiniteQuery for feed pagination
│   ├── use-settings.ts # Settings CRUD mutations
│   └── use-auth.ts     # Auth state (login, logout, check)
├── lib/
│   ├── api.ts          # Fetch wrapper with cookie auth
│   └── query-keys.ts   # TanStack Query key factory
└── styles/
    └── globals.css     # Tailwind v4 imports + BasaltUI theme
```

## Routes

File-based routing with TanStack Router. Each route file exports `createFileRoute`:

| Path | File | Component | Data |
|------|------|-----------|------|
| `/` | `routes/index.tsx` | Feed | `useInfiniteQuery` → `GET /api/v1/feed?cursor=&tag=` |
| `/article/$topicId` | `routes/article.$topicId.tsx` | Article | Type-safe params + `useCompletion` for streaming |
| `/settings` | `routes/settings.tsx` | Settings | `useQuery` + `useMutation` for settings/sources |
| `/login` | `routes/login.tsx` | Login | `POST /api/v1/auth/login` |

**Type-Safe Navigation:**
```typescript
import { useNavigate } from '@tanstack/react-router';

// ✅ Type-safe - params autocompleted
navigate({ to: '/article/$topicId', params: { topicId: '123' } });

// ✅ Type-safe search params with Zod validation
navigate({
  to: '/',
  search: (prev) => ({ ...prev, tag: 'ai', cursor: '2026-02-07' })
});
```

## React Patterns

- **Named exports only** — no default exports
- **Function components** — no `React.FC`, no class components
- **Hooks** — custom hooks in `hooks/` for data fetching logic
- **Colocation** — component-specific types defined in the same file

```typescript
// ✅ Correct
export function TopicCard({ topic }: { topic: Topic }) { ... }

// ❌ Wrong
export default function TopicCard(...) { ... }
const TopicCard: React.FC<Props> = ...
```

## Streaming (Article Generation)

Use `useCompletion` (one-shot), NOT `useChat` (multi-turn conversational).

```typescript
import { useCompletion } from '@ai-sdk/react';

export function ArticlePage({ topicId }: { topicId: string }) {
  const { completion, isLoading, complete } = useCompletion({
    api: `/api/v1/article/${topicId}/generate`,
  });

  // completion = streamed markdown text
  // complete() triggers the POST request
  // Render with streamdown
}
```

## Markdown Rendering (streamdown)

Use `streamdown` for AI-streaming markdown. NOT `react-markdown`.

```typescript
import { useStreamdown } from 'streamdown/react';

function ArticleContent({ content }: { content: string }) {
  const { ref } = useStreamdown(content);
  return <div ref={ref} className="prose" />;
}
```

## Tailwind v4

CSS-first configuration. NO `tailwind.config.js`.

```css
/* globals.css */
@import "tailwindcss";

/* BasaltUI theme tokens imported here */
@import "@basalt-ui/styles";
```

## TanStack Query

See `/tanstack-query` skill for comprehensive patterns. Key patterns:

- `useInfiniteQuery` for feed (cursor-based pagination)
- Query key factory in `lib/query-keys.ts`
- Prefetch on hover for article pages
- Optimistic updates for source CRUD

## ShadCN/ui + BasaltUI

Install components via CLI:

```bash
bunx --bun shadcn@latest add button card input dialog select
```

BasaltUI provides design tokens (colors, spacing, typography). ShadCN components use those tokens via Tailwind classes.
