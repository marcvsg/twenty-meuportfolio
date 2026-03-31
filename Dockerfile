# Build stage
FROM node:24.5.0-alpine AS builder
WORKDIR /app

# Install corepack
RUN npm install -g corepack@latest && corepack enable

# Copy only package files first (for better cache layers)
COPY package.json yarn.lock .yarnrc.yml ./

# Install dependencies
RUN yarn install --immutable --network-timeout=120000

# Copy source code
COPY . .

# Build only twenty-server
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
COPY --from=builder /app/package.json ./

# Set ownership
RUN chown -R nodejs:nodejs /app

USER nodejs

EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/main.js"]
