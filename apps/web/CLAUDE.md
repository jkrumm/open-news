# OpenNews Web

React 19 SPA with Vite, TanStack Query, Tailwind v4, and AI SDK streaming.

## Stack

- **Framework**: React 19 + react-router-dom 7
- **Build**: Vite (with `@vitejs/plugin-react`)
- **State**: TanStack Query v5 (server state), React state (local UI)
- **Styling**: Tailwind v4 (CSS-first) + ShadCN/ui + BasaltUI theme
- **Streaming**: `useCompletion` from `@ai-sdk/react` + `streamdown` for markdown
- **Icons**: lucide-react

## Directory Structure

```
src/
├── main.tsx            # React entry point
├── App.tsx             # Router setup (react-router-dom)
├── routes/
│   ├── Feed.tsx        # Daily feed with infinite scroll
│   ├── Article.tsx     # Deep-dive article with streaming
│   ├── Settings.tsx    # Preferences and source management
│   └── Login.tsx       # Auth (single secret input)
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

| Path | Component | Data |
|------|-----------|------|
| `/` | Feed | `useInfiniteQuery` → `GET /api/v1/feed?cursor=&tag=` |
| `/article/:id` | Article | `useQuery` + `useCompletion` for streaming |
| `/settings` | Settings | `useQuery` + `useMutation` for settings/sources |
| `/login` | Login | `POST /api/v1/auth/login` |

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
