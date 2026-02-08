// Domain types and constants

// ─── Source Types ─────────────────────────────────────────────
export const SOURCE_TYPES = ['rss', 'hackernews', 'tavily'] as const;
export type SourceType = (typeof SOURCE_TYPES)[number];

// ─── Topic Types ─────────────────────────────────────────────
export const TOPIC_TYPES = ['hot', 'normal', 'standalone'] as const;
export type TopicType = (typeof TOPIC_TYPES)[number];

// ─── News Styles ─────────────────────────────────────────────
export const NEWS_STYLES = ['concise', 'detailed', 'technical'] as const;
export type NewsStyle = (typeof NEWS_STYLES)[number];

// ─── Settings ─────────────────────────────────────────────────
export interface Settings {
  id: number;
  displayName: string;
  background: string;
  interests: string;
  newsStyle: NewsStyle;
  language: string;
  timezone: string;
  topics: string[];
  searchQueries: string[];
  updatedAt: string;
}

// ─── Source ───────────────────────────────────────────────────
export interface Source {
  id: number;
  name: string;
  url: string;
  type: SourceType;
  enabled: boolean;
  etag: string | null;
  lastModified: string | null;
  lastFetchedAt: string | null;
  createdAt: string;
}

// ─── Raw Article ──────────────────────────────────────────────
export interface RawArticle {
  id: number;
  sourceId: number | null;
  externalId: string | null;
  title: string;
  url: string;
  urlNormalized: string;
  content: string | null;
  snippet: string | null;
  author: string | null;
  score: number | null;
  publishedAt: string | null;
  scrapedAt: string;
  scrapedDate: string;
}

// ─── Daily Topic ──────────────────────────────────────────────
export interface DailyTopic {
  id: number;
  date: string;
  topicType: TopicType;
  headline: string;
  summary: string;
  relevanceScore: number;
  sourceCount: number;
  createdAt: string;
}

// ─── Tag ──────────────────────────────────────────────────────
export interface Tag {
  id: number;
  name: string;
  color: string | null;
}

// ─── Generated Article ────────────────────────────────────────
export interface GeneratedArticle {
  id: number;
  topicId: number;
  content: string;
  generatedAt: string;
}

// ─── API Request/Response Types ──────────────────────────────

// Auth
export interface LoginRequest {
  secret: string;
}

export interface AuthCheckResponse {
  authenticated: boolean;
}

// Settings
export type SettingsUpdateRequest = Partial<Omit<Settings, 'id' | 'updatedAt'>>;

// Sources
export interface CreateSourceRequest {
  name: string;
  url: string;
  type: SourceType;
}

export type UpdateSourceRequest = Partial<Omit<Source, 'id' | 'createdAt'>>;

// Feed
export interface DayWithTopics {
  date: string;
  topics: TopicWithDetails[];
}

export interface TopicWithDetails extends DailyTopic {
  tags: Tag[];
  sources: RawArticle[];
}

export interface FeedResponse {
  days: DayWithTopics[];
  nextCursor?: string;
}

export interface FeedQueryParams {
  cursor?: string;
  limit?: number;
  tag?: string;
}

// Article
export interface ArticleResponse {
  cached: boolean;
  content?: string;
}

// Admin
export interface AdminStatusResponse {
  lastDigest: string | null;
  articleCount: number;
  sourceCount: number;
  nextScheduledRun: string | null;
}

// Health
export interface HealthResponse {
  status: 'ok';
  timestamp: string;
}
