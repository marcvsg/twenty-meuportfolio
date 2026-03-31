# Build stage
FROM node:24.5.0-alpine AS builder
WORKDIR /app

# Install corepack
RUN npm install -g corepack@latest && corepack enable

# Copy only package files first
COPY package.json yarn.lock .yarnrc.yml ./
COPY packages/twenty-server/package.json ./packages/twenty-server/
COPY packages/twenty-shared/package.json ./packages/twenty-shared/
COPY packages/twenty-ui/package.json ./packages/twenty-ui/
COPY packages/twenty-utils/package.json ./packages/twenty-utils/
COPY packages/twenty-emails/package.json ./packages/twenty-emails/

# Install dependencies
RUN yarn install --immutable --network-timeout=120000

# Copy source code
COPY . .

# Build dependencies first, then server
RUN yarn nx build twenty-shared
RUN yarn nx build twenty-server

# Production stage
FROM node:24.5.0-alpine
WORKDIR /app

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy only necessary files from builder
COPY --from=builder /app/packages/twenty-server/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/twenty-shared/dist ./packages/twenty-shared/dist
COPY --from=builder /app/package.json ./

# Set ownership
RUN chown -R nodejs:nodejs /app

USER nodejs

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})" || exit 1

EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/main.js"]
