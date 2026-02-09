// Zod schemas for API validation
import { z } from 'zod';
import { NEWS_STYLES, SOURCE_TYPES, TOPIC_TYPES } from './types';

// ─── Settings ─────────────────────────────────────────────────

export const settingsSchema = z.object({
  id: z.number().default(1),
  displayName: z.string().default(''),
  background: z.string().default(''),
  interests: z.string().default(''),
  newsStyle: z.enum(NEWS_STYLES).default('concise'),
  language: z.string().default('en'),
  timezone: z.string().default('Europe/Berlin'),
  topics: z.array(z.string()).default([]),
  searchQueries: z.array(z.string()).default([]),
  updatedAt: z.string(),
});

export const settingsUpdateSchema = settingsSchema.omit({ id: true, updatedAt: true }).partial();

// ─── Sources ──────────────────────────────────────────────────

export const sourceSchema = z.object({
  id: z.number(),
  name: z.string().min(1, 'Name is required'),
  url: z.string().url('Invalid URL'),
  type: z.enum(SOURCE_TYPES),
  enabled: z.boolean().default(true),
  etag: z.string().nullable(),
  lastModified: z.string().nullable(),
  lastFetchedAt: z.string().nullable(),
  createdAt: z.string(),
});

export const createSourceSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  url: z.string().url('Invalid URL'),
  type: z.enum(SOURCE_TYPES),
});

export const updateSourceSchema = sourceSchema.omit({ id: true, createdAt: true }).partial();

// ─── Auth ─────────────────────────────────────────────────────

export const loginRequestSchema = z.object({
  secret: z.string().min(1, 'Secret is required'),
});

// ─── Feed ─────────────────────────────────────────────────────

export const feedQueryParamsSchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().min(1).max(30).default(3),
  tag: z.string().optional(),
});

// ─── Topic ────────────────────────────────────────────────────

export const topicTypeSchema = z.enum(TOPIC_TYPES);

// ─── Raw Article ──────────────────────────────────────────────

export const rawArticleSchema = z.object({
  id: z.number(),
  sourceId: z.number().nullable(),
  externalId: z.string().nullable(),
  title: z.string(),
  url: z.string().url(),
  urlNormalized: z.string(),
  content: z.string().nullable(),
  snippet: z.string().nullable(),
  author: z.string().nullable(),
  score: z.number().nullable(),
  publishedAt: z.string().nullable(),
  scrapedAt: z.string(),
  scrapedDate: z.string(),
});

// ─── Pipeline Adapter Schemas ─────────────────────────────────

export const discoveredArticleSchema = z.object({
  title: z.string(),
  url: z.string().url(),
  snippet: z.string().nullable(),
  author: z.string().nullable(),
  publishedAt: z.string().nullable(),
  externalId: z.string().nullable(),
  score: z.number().nullable(),
  sourceType: z.enum(SOURCE_TYPES),
});

export const extractedContentSchema = z.object({
  title: z.string().nullable(),
  content: z.string().min(1),
  author: z.string().nullable(),
  publishedAt: z.string().nullable(),
  siteName: z.string().nullable(),
  excerpt: z.string().nullable(),
});

// ─── Daily Topic ──────────────────────────────────────────────

export const dailyTopicSchema = z.object({
  id: z.number(),
  date: z.string(),
  topicType: topicTypeSchema,
  headline: z.string(),
  summary: z.string(),
  relevanceScore: z.number().min(0).max(1),
  sourceCount: z.number().min(1),
  createdAt: z.string(),
});

// ─── Tag ──────────────────────────────────────────────────────

export const tagSchema = z.object({
  id: z.number(),
  name: z.string().min(1),
  color: z.string().nullable(),
});
