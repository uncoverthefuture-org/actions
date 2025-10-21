# syntax=docker/dockerfile:1
FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
RUN if [ -f pnpm-lock.yaml ]; then npm i -g pnpm && pnpm i --frozen-lockfile; \
    elif [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
    else npm ci; fi
COPY . .
RUN if [ -f pnpm-lock.yaml ]; then npm i -g pnpm && pnpm run build; \
    elif [ -f yarn.lock ]; then yarn build; \
    else npm run build; fi

FROM node:18-alpine AS runner
WORKDIR /app
RUN npm i -g serve
COPY --from=deps /app/build ./build
EXPOSE 3000
ENV TARGET_PORT=3000
CMD sh -c "serve -s build -l ${TARGET_PORT:-3000}"
