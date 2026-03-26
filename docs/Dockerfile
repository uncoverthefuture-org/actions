# syntax=docker/dockerfile:1

FROM node:20-bullseye-slim AS base
WORKDIR /app
RUN corepack enable
ENV YARN_NODE_LINKER=node-modules

FROM base AS deps
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
RUN yarn install --immutable

FROM deps AS dev
ENV NODE_ENV=development
COPY . .
CMD ["yarn", "dev", "--host", "0.0.0.0", "--port", "3000"]

FROM deps AS builder
ENV NODE_ENV=production
COPY . .
RUN yarn build

# Production runner using 'serve' (static file server)
FROM node:20-bullseye-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# Install 'serve' globally to serve static files
RUN yarn global add serve

# Copy built assets from builder stage
COPY --from=builder /app/dist ./dist

EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
