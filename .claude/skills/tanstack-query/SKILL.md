---
name: tanstack-query
description: TanStack Query v5 patterns for React. Reference for queries, mutations, infinite scroll, and cache management.
context: fork
user_invocable: true
---

# TanStack Query v5 Patterns

Quick reference for `@tanstack/react-query` v5 patterns used in OpenNews.

## Setup

```typescript
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,  // 5 minutes
      retry: 1,
    },
  },
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  );
}
```

## Query Keys Convention

```typescript
// Use factory pattern for type-safe keys
export const queryKeys = {
  feed: {
    all: ['feed'] as const,
    list: (filters: { tag?: string }) => ['feed', 'list', filters] as const,
  },
  article: {
    all: ['article'] as const,
    detail: (topicId: string) => ['article', topicId] as const,
  },
  settings: ['settings'] as const,
  sources: ['sources'] as const,
  tags: ['tags'] as const,
} as const;
```

## Standard Query

```typescript
import { useQuery } from '@tanstack/react-query';

function useSettings() {
  return useQuery({
    queryKey: queryKeys.settings,
    queryFn: () => api.get<Settings>('/api/v1/settings'),
  });
}
```

## Mutation with Cache Invalidation

```typescript
import { useMutation, useQueryClient } from '@tanstack/react-query';

function useUpdateSettings() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: Partial<Settings>) => api.put('/api/v1/settings', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.settings });
    },
  });
}
```

## Infinite Query (Feed Pagination)

This is the primary pattern for the daily feed with cursor-based pagination.

```typescript
import { useInfiniteQuery } from '@tanstack/react-query';

interface FeedResponse {
  days: DayWithTopics[];
  nextCursor?: string;
}

function useFeed(tag?: string) {
  return useInfiniteQuery({
    queryKey: queryKeys.feed.list({ tag }),
    queryFn: async ({ pageParam }) => {
      const params = new URLSearchParams();
      if (pageParam) params.set('cursor', pageParam);
      if (tag) params.set('tag', tag);
      params.set('limit', '3');
      return api.get<FeedResponse>(`/api/v1/feed?${params}`);
    },
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (lastPage) => lastPage.nextCursor,
  });
}

// In component:
function Feed() {
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useFeed(selectedTag);

  const allDays = data?.pages.flatMap((page) => page.days) ?? [];

  // Intersection observer for infinite scroll
  const observerRef = useRef<IntersectionObserver>();
  const loadMoreRef = useCallback((node: HTMLDivElement | null) => {
    if (isFetchingNextPage) return;
    if (observerRef.current) observerRef.current.disconnect();
    observerRef.current = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting && hasNextPage) {
        fetchNextPage();
      }
    });
    if (node) observerRef.current.observe(node);
  }, [isFetchingNextPage, hasNextPage, fetchNextPage]);

  return (
    <>
      {allDays.map((day) => <DaySection key={day.date} day={day} />)}
      <div ref={loadMoreRef} />
    </>
  );
}
```

## Optimistic Update

```typescript
function useDeleteSource() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: number) => api.delete(`/api/v1/sources/${id}`),
    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: queryKeys.sources });
      const previous = queryClient.getQueryData<Source[]>(queryKeys.sources);
      queryClient.setQueryData<Source[]>(queryKeys.sources, (old) =>
        old?.filter((s) => s.id !== id),
      );
      return { previous };
    },
    onError: (_err, _id, context) => {
      queryClient.setQueryData(queryKeys.sources, context?.previous);
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: queryKeys.sources });
    },
  });
}
```

## Conditional Fetching

```typescript
function useArticle(topicId: string) {
  return useQuery({
    queryKey: queryKeys.article.detail(topicId),
    queryFn: () => api.get<{ cached: boolean; content?: string }>(`/api/v1/article/${topicId}`),
    enabled: !!topicId,
  });
}
```

## Prefetching

```typescript
// Prefetch on hover for perceived speed
function TopicCard({ topic }: { topic: Topic }) {
  const queryClient = useQueryClient();

  const handleMouseEnter = () => {
    queryClient.prefetchQuery({
      queryKey: queryKeys.article.detail(String(topic.id)),
      queryFn: () => api.get(`/api/v1/article/${topic.id}`),
      staleTime: 60 * 1000,
    });
  };

  return <Link to={`/article/${topic.id}`} onMouseEnter={handleMouseEnter}>...</Link>;
}
```
