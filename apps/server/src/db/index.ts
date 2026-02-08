// Database connection with WAL mode and pragmas
// Using Bun's built-in SQLite driver (bun:sqlite)

import { Database } from 'bun:sqlite';
import { drizzle } from 'drizzle-orm/bun-sqlite';
import * as schema from './schema';

// Database path from environment or default
const DATABASE_PATH = process.env.DATABASE_PATH ?? './data/open-news.db';

// Initialize SQLite connection
const sqlite = new Database(DATABASE_PATH);

// Configure SQLite pragmas for optimal performance and safety
sqlite.run('PRAGMA journal_mode = WAL'); // Write-Ahead Logging for concurrent reads
sqlite.run('PRAGMA busy_timeout = 5000'); // Wait up to 5s if database is locked
sqlite.run('PRAGMA synchronous = NORMAL'); // Balance between safety and performance
sqlite.run('PRAGMA foreign_keys = ON'); // Enable foreign key constraints

// Initialize Drizzle ORM with schema
export const db = drizzle(sqlite, { schema });

// Export raw SQLite instance for direct operations if needed
export { sqlite };
