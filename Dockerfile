# ============================================
# Stage 1: Install all dependencies
# ============================================
FROM oven/bun:1 AS deps

WORKDIR /app

COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/
COPY packages/shared/package.json ./packages/shared/

RUN bun install --frozen-lockfile

# ============================================
# Stage 2: Build React SPA
# ============================================
FROM deps AS build-web

WORKDIR /app

COPY packages/shared/ ./packages/shared/
COPY apps/web/ ./apps/web/

RUN bun run --cwd apps/web build

# ============================================
# Stage 3: Production runtime
# ============================================
FROM oven/bun:1-slim AS runtime

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Copy workspace config + install production deps
COPY package.json bun.lock ./
COPY apps/server/package.json ./apps/server/
COPY packages/shared/package.json ./packages/shared/

RUN bun install --frozen-lockfile --production

# Copy source code (Bun runs TS directly)
COPY packages/shared/ ./packages/shared/
COPY apps/server/ ./apps/server/

# Copy built frontend
COPY --from=build-web /app/apps/web/dist ./apps/web/dist

# Create data directory
RUN mkdir -p /app/data && chown -R bun:bun /app/data

USER bun

ENV NODE_ENV=production
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["bun", "run", "apps/server/src/index.ts"]
