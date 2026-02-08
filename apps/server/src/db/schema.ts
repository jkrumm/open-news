// SQLite schema for OpenNews
// Full schema from SPEC.md §4 Data Model

import { index, integer, real, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

// ─── User Settings (single row) ───────────────────────────
export const settings = sqliteTable('settings', {
  id: integer('id').primaryKey().default(1),
  // Personal profile
  displayName: text('display_name').notNull().default(''),
  background: text('background').notNull().default(''), // e.g. "Senior Full-Stack Developer"
  interests: text('interests').notNull().default(''), // free-text description
  newsStyle: text('news_style').notNull().default('concise'), // 'concise' | 'detailed' | 'technical'
  language: text('language').notNull().default('en'), // output language
  timezone: text('timezone').notNull().default('Europe/Berlin'),
  // Topics of interest (JSON array of strings)
  topics: text('topics', { mode: 'json' }).notNull().default('[]').$type<string[]>(),
  // Tavily search queries (JSON array of strings)
  searchQueries: text('search_queries', { mode: 'json' }).notNull().default('[]').$type<string[]>(),
  updatedAt: text('updated_at')
    .notNull()
    .$defaultFn(() => new Date().toISOString()),
});

// ─── Feed Sources ─────────────────────────────────────────
export const sources = sqliteTable('sources', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull(),
  url: text('url').notNull().unique(),
  type: text('type').notNull(), // 'rss' | 'hackernews' | 'tavily'
  enabled: integer('enabled', { mode: 'boolean' }).notNull().default(true),
  // RSS-specific
  etag: text('etag'), // for conditional fetching
  lastModified: text('last_modified'), // for conditional fetching
  lastFetchedAt: text('last_fetched_at'),
  createdAt: text('created_at')
    .notNull()
    .$defaultFn(() => new Date().toISOString()),
});

// ─── Raw Articles (scraped from sources) ──────────────────
export const rawArticles = sqliteTable(
  'raw_articles',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    sourceId: integer('source_id').references(() => sources.id),
    externalId: text('external_id'), // HN story ID, RSS guid, etc.
    title: text('title').notNull(),
    url: text('url').notNull(),
    urlNormalized: text('url_normalized').notNull().unique(), // for dedup
    content: text('content'), // extracted full text (nullable, stored in DB)
    snippet: text('snippet'), // short excerpt
    author: text('author'),
    score: integer('score'), // HN score, null for RSS
    publishedAt: text('published_at'),
    scrapedAt: text('scraped_at')
      .notNull()
      .$defaultFn(() => new Date().toISOString()),
    scrapedDate: text('scraped_date').notNull(), // YYYY-MM-DD for daily grouping
  },
  (table) => ({
    dateIdx: index('raw_articles_date_idx').on(table.scrapedDate),
    urlIdx: uniqueIndex('raw_articles_url_idx').on(table.urlNormalized),
  }),
);

// ─── Daily Topics (AI-grouped headlines) ──────────────────
// Topic types: 'hot' = main stories of the day, 'normal' = regular grouped topics,
// 'standalone' = individually interesting articles (guides, tutorials, etc.) not grouped into a topic
export const dailyTopics = sqliteTable(
  'daily_topics',
  {
    id: integer('id').primaryKey({ autoIncrement: true }),
    date: text('date').notNull(), // YYYY-MM-DD
    topicType: text('topic_type').notNull().default('normal'), // 'hot' | 'normal' | 'standalone'
    headline: text('headline').notNull(), // AI-generated headline
    summary: text('summary').notNull(), // AI-generated summary (2-3 sentences)
    relevanceScore: real('relevance_score').notNull().default(0), // 0-1, AI-scored based on user interests
    sourceCount: integer('source_count').notNull().default(1),
    createdAt: text('created_at')
      .notNull()
      .$defaultFn(() => new Date().toISOString()),
  },
  (table) => ({
    dateIdx: index('daily_topics_date_idx').on(table.date),
  }),
);

// ─── Tags ─────────────────────────────────────────────────
export const tags = sqliteTable('tags', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  name: text('name').notNull().unique(), // e.g. 'ai', 'typescript', 'finance'
  color: text('color'), // optional hex color (deferred, null for MVP)
});

// ─── Topic <-> Tag (many-to-many) ─────────────────────────
export const topicTags = sqliteTable(
  'topic_tags',
  {
    topicId: integer('topic_id')
      .notNull()
      .references(() => dailyTopics.id, { onDelete: 'cascade' }),
    tagId: integer('tag_id')
      .notNull()
      .references(() => tags.id, { onDelete: 'cascade' }),
  },
  (table) => ({
    topicIdx: index('topic_tags_topic_idx').on(table.topicId),
  }),
);

// ─── Topic <-> Raw Article (many-to-many) ─────────────────
export const topicSources = sqliteTable(
  'topic_sources',
  {
    topicId: integer('topic_id')
      .notNull()
      .references(() => dailyTopics.id, { onDelete: 'cascade' }),
    rawArticleId: integer('raw_article_id')
      .notNull()
      .references(() => rawArticles.id, { onDelete: 'cascade' }),
  },
  (table) => ({
    topicIdx: index('topic_sources_topic_idx').on(table.topicId),
  }),
);

// ─── Generated Articles (cached deep-dives) ──────────────
export const generatedArticles = sqliteTable('generated_articles', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  topicId: integer('topic_id')
    .notNull()
    .references(() => dailyTopics.id, { onDelete: 'cascade' })
    .unique(),
  content: text('content').notNull(), // markdown (stored in DB)
  generatedAt: text('generated_at')
    .notNull()
    .$defaultFn(() => new Date().toISOString()),
});
