// Pino logger factory with shared configuration
import pino, { type Logger, type LoggerOptions } from 'pino';

const isDev = process.env.NODE_ENV !== 'production';

export function createLogger(service: string): Logger {
  const options: LoggerOptions = {
    level: process.env.LOG_LEVEL ?? (isDev ? 'debug' : 'info'),
    timestamp: pino.stdTimeFunctions.isoTime,
    transport: isDev
      ? {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'HH:MM:ss.l',
            ignore: 'pid,hostname',
          },
        }
      : undefined,
  };

  return pino(options).child({ service });
}

export type { Logger } from 'pino';
