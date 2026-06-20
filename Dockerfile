# MagSlide MCP server — isolated runtime for the Google Slides MCP.
# Multi-stage: deps are installed with --ignore-scripts (no lifecycle code runs),
# the final image runs as the non-root `node` user with no host filesystem access.

FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:24-alpine AS prod
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=build /app/build ./build
USER node
ENTRYPOINT ["node", "build/index.js"]
