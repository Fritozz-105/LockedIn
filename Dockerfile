# Production image for the API ONLY. The mobile app is not containerized — it
# ships via EAS Build. Multi-stage so the runtime image carries no build tools,
# dev deps, or source.

FROM node:20-alpine AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable
WORKDIR /app

# ---- build: install, compile shared + api, prune to a prod deployment ----
FROM base AS build
COPY . .
# Install only the API and its workspace deps (skips the mobile app's tree).
RUN pnpm install --frozen-lockfile --filter @lockedin/api...
# shared must be built before api (api imports its compiled dist).
RUN pnpm --filter @lockedin/shared build \
 && pnpm --filter @lockedin/api build
# Self-contained prod deployment: api's dist + @lockedin/shared injected into
# node_modules, prod deps only. Target is OUTSIDE /app so pnpm won't refuse to
# deploy into the workspace it's reading from.
RUN pnpm --filter @lockedin/api deploy --prod /prod

# ---- runtime: minimal image with just the pruned deployment ----
FROM base AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /prod ./
# Heroku injects PORT; the server reads env.PORT and binds 0.0.0.0.
CMD ["node", "dist/server.js"]
