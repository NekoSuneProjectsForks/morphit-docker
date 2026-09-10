# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=24

FROM node:${NODE_VERSION}-bookworm-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       ca-certificates \
       pkg-config \
       python3 \
    && rm -rf /var/lib/apt/lists/*

COPY upstream/ /app/

RUN test -f package.json && test -f package-lock.json
RUN npm ci

# Use Morphit's own documented workspace build command. Release bundles may
# already contain canonical web output; upstream's build guard decides whether
# that output is preserved or rebuilt.
RUN npm run build --workspaces --if-present

# Keep only production dependencies in the runtime image. Morphit's indexer,
# relay and matrix bot currently keep tsx in production dependencies.
RUN npm prune --omit=dev


FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG MORPHIT_VERSION=unknown

LABEL org.opencontainers.image.title="Morphit Docker" \
      org.opencontainers.image.description="Unofficial multi-arch Docker wrapper for Agorise Morphit releases" \
      org.opencontainers.image.source="https://git.agorise.net/agorise/morphit" \
      org.opencontainers.image.url="https://github.com/NekoSuneProjectsForks/morphit-docker" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${MORPHIT_VERSION}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       dumb-init \
       nginx-light \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder --chown=node:node /app /app
COPY --chown=node:node docker/entrypoint.sh /usr/local/bin/morphit-entrypoint
COPY --chown=node:node docker/nginx.conf /opt/morphit-docker/nginx.conf

RUN chmod 0755 /usr/local/bin/morphit-entrypoint

ENV NODE_ENV=production \
    PORT=8080

EXPOSE 8080

USER node

ENTRYPOINT ["dumb-init", "--", "/usr/local/bin/morphit-entrypoint"]
CMD ["web"]
