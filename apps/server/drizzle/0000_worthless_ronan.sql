CREATE TABLE `daily_topics` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`date` text NOT NULL,
	`topic_type` text DEFAULT 'normal' NOT NULL,
	`headline` text NOT NULL,
	`summary` text NOT NULL,
	`relevance_score` real DEFAULT 0 NOT NULL,
	`source_count` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `daily_topics_date_idx` ON `daily_topics` (`date`);--> statement-breakpoint
CREATE TABLE `generated_articles` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`topic_id` integer NOT NULL,
	`content` text NOT NULL,
	`generated_at` text NOT NULL,
	FOREIGN KEY (`topic_id`) REFERENCES `daily_topics`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `generated_articles_topic_id_unique` ON `generated_articles` (`topic_id`);--> statement-breakpoint
CREATE TABLE `raw_articles` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`source_id` integer,
	`external_id` text,
	`title` text NOT NULL,
	`url` text NOT NULL,
	`url_normalized` text NOT NULL,
	`content` text,
	`snippet` text,
	`author` text,
	`score` integer,
	`published_at` text,
	`scraped_at` text NOT NULL,
	`scraped_date` text NOT NULL,
	FOREIGN KEY (`source_id`) REFERENCES `sources`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `raw_articles_url_normalized_unique` ON `raw_articles` (`url_normalized`);--> statement-breakpoint
CREATE INDEX `raw_articles_date_idx` ON `raw_articles` (`scraped_date`);--> statement-breakpoint
CREATE UNIQUE INDEX `raw_articles_url_idx` ON `raw_articles` (`url_normalized`);--> statement-breakpoint
CREATE TABLE `settings` (
	`id` integer PRIMARY KEY DEFAULT 1 NOT NULL,
	`display_name` text DEFAULT '' NOT NULL,
	`background` text DEFAULT '' NOT NULL,
	`interests` text DEFAULT '' NOT NULL,
	`news_style` text DEFAULT 'concise' NOT NULL,
	`language` text DEFAULT 'en' NOT NULL,
	`timezone` text DEFAULT 'Europe/Berlin' NOT NULL,
	`topics` text DEFAULT '[]' NOT NULL,
	`search_queries` text DEFAULT '[]' NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `sources` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`url` text NOT NULL,
	`type` text NOT NULL,
	`enabled` integer DEFAULT true NOT NULL,
	`etag` text,
	`last_modified` text,
	`last_fetched_at` text,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `sources_url_unique` ON `sources` (`url`);--> statement-breakpoint
CREATE TABLE `tags` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`color` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `tags_name_unique` ON `tags` (`name`);--> statement-breakpoint
CREATE TABLE `topic_sources` (
	`topic_id` integer NOT NULL,
	`raw_article_id` integer NOT NULL,
	FOREIGN KEY (`topic_id`) REFERENCES `daily_topics`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`raw_article_id`) REFERENCES `raw_articles`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `topic_sources_topic_idx` ON `topic_sources` (`topic_id`);--> statement-breakpoint
CREATE TABLE `topic_tags` (
	`topic_id` integer NOT NULL,
	`tag_id` integer NOT NULL,
	FOREIGN KEY (`topic_id`) REFERENCES `daily_topics`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`tag_id`) REFERENCES `tags`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `topic_tags_topic_idx` ON `topic_tags` (`topic_id`);