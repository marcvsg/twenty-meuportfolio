# Build stage for dependencies
FROM node:24.5.0-alpine AS deps
WORKDIR /app

# Install corepack
RUN npm install -g corepack@latest && corepack enable

# Copy only package files to leverage Docker cache
COPY package.json yarn.lock .yarnrc.yml ./
COPY packages/twenty-server/package.json ./packages/twenty-server/
COPY packages/twenty-shared/package.json ./packages/twenty-shared/
COPY packages/twenty-ui/package.json ./packages/twenty-ui/
COPY packages/twenty-utils/package.json ./packages/twenty-utils/
COPY packages/twenty-emails/package.json ./packages/twenty-emails/

# Install dependencies (with cache)
RUN --mount=type=cache,target=/root/.yarn \
    yarn install --immutable --network-timeout=60000

# Build stage
FROM node:24.5.0-alpine AS builder
WORKDIR /app

# Copy from deps
COPY --from=deps /app .

# Copy source code
COPY . .

# Build only twenty-server and dependencies
RUN --mount=type=cache,target=/root/.yarn \
    yarn nx build twenty-shared && \
    yarn nx build twenty-server

# Production stage
FROM node:24.5.0-alpine
WORKDIR /app

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built app from builder
COPY --from=builder /app/packages/twenty-server/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/twenty-shared/dist ./packages/twenty-shared/dist

# Set ownership
RUN chown -R nodejs:nodejs /app

USER nodejs

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/main.js"]
