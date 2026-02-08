// Migration runner for applying Drizzle migrations
// Run with: bun run src/db/migrate.ts

import { createLogger } from '@open-news/shared';
import { migrate } from 'drizzle-orm/bun-sqlite/migrator';
import { db, sqlite } from './index';

const logger = createLogger('migrate');

async function runMigrations() {
  try {
    logger.info('Starting database migrations...');
    await migrate(db, { migrationsFolder: './drizzle' });
    logger.info('Migrations completed successfully');
    sqlite.close();
    process.exit(0);
  } catch (error) {
    logger.error({ error }, 'Migration failed');
    sqlite.close();
    process.exit(1);
  }
}

runMigrations();
