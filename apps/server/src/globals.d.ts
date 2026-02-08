// Bun runtime globals
declare const console: Console;

interface Console {
  log(...args: unknown[]): void;
  error(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  info(...args: unknown[]): void;
  debug(...args: unknown[]): void;
}

// Hono context extensions
import type { Logger } from 'pino';

declare module 'hono' {
  interface ContextVariableMap {
    logger: Logger;
  }
}
