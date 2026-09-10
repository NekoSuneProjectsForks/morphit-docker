# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=24
ARG PYTHON_VERSION=3.13

# -----------------------------------------------------------------------------
# Official Morphit source stage
# -----------------------------------------------------------------------------
# The Docker build itself downloads Morphit from the official Agorise Forgejo
# repository. The helper talks only to:
#   https://git.agorise.net/api/v1/repos/agorise/morphit
# It selects the requested published release, downloads the official .tar.gz
# plus its .sha256 asset, verifies SHA-256, and safely extracts it.
#
# BUILDPLATFORM is intentional: the source archive is architecture-independent,
# so Buildx can reuse this stage while the Node build still runs for each target
# architecture (linux/amd64 and linux/arm64).
FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}-slim AS morphit-source

ARG MORPHIT_TAG=latest

WORKDIR /fetch

COPY scripts/fetch-release.py /usr/local/bin/fetch-morphit-release

RUN chmod 0755 /usr/local/bin/fetch-morphit-release \
    && if [ -z "$MORPHIT_TAG" ] || [ "$MORPHIT_TAG" = "latest" ]; then \
         resolved_tag="$(python3 /usr/local/bin/fetch-morphit-release --output /morphit)"; \
       else \
         resolved_tag="$(python3 /usr/local/bin/fetch-morphit-release --tag "$MORPHIT_TAG" --output /morphit)"; \
       fi \
    && test -n "$resolved_tag" \
    && test -f /morphit/package.json \
    && test -f /morphit/package-lock.json \
    && printf '%s\n' "$resolved_tag" > /morphit/.morphit-release \
    && echo "Using official Agorise Morphit release: $resolved_tag"


# -----------------------------------------------------------------------------
# Morphit build stage - runs for the target architecture
# -----------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       ca-certificates \
       pkg-config \
       python3 \
    && rm -rf /var/lib/apt/lists/*

# Source comes only from the verified official release downloaded above.
COPY --from=morphit-source /morphit/ /app/

RUN test -f package.json \
    && test -f package-lock.json \
    && test -f .morphit-release

RUN npm ci

# Use Morphit's own workspace build commands. Official release bundles may
# already contain canonical web output; Morphit's own build guard decides
# whether that output is preserved or rebuilt.
RUN npm run build --workspaces --if-present

# Keep only production dependencies in the runtime image. Morphit's indexer,
# relay and matrix bot currently keep tsx in production dependencies.
RUN npm prune --omit=dev


# -----------------------------------------------------------------------------
# Runtime image
# -----------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG MORPHIT_TAG=latest

LABEL org.opencontainers.image.title="Morphit Docker" \
      org.opencontainers.image.description="Unofficial multi-arch Docker wrapper built directly from official Agorise Morphit releases" \
      org.opencontainers.image.source="https://git.agorise.net/agorise/morphit" \
      org.opencontainers.image.url="https://github.com/NekoSuneProjectsForks/morphit-docker" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${MORPHIT_TAG}"

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
