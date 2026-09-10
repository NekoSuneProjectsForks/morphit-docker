# morphit-docker

Unofficial multi-architecture Docker wrapper for [Agorise Morphit](https://git.agorise.net/agorise/morphit).

This repository does **not** mirror Morphit's `main` branch and does not rebuild on every upstream commit. It follows published Morphit releases only.

## Official upstream source

The Dockerfile itself downloads Morphit from the official Agorise Forgejo repository. It does **not** depend on a copied or mirrored Morphit source tree stored in this GitHub repository.

During `docker build`, the `morphit-source` stage runs `scripts/fetch-release.py`, which talks to:

```text
https://git.agorise.net/api/v1/repos/agorise/morphit
```

The source stage:

1. resolves the requested published Morphit release,
2. downloads the official release `.tar.gz` asset from Agorise,
3. downloads the matching official `.sha256` asset,
4. verifies the archive SHA-256,
5. safely extracts the release into `/morphit`,
6. copies that verified official source into the Node build stage,
7. runs `npm ci` and Morphit's workspace build commands.

The final image retains the upstream source under `/app` and records the resolved release in `/app/.morphit-release`.

## Image

The workflow publishes one reusable image:

```text
ghcr.io/nekosuneprojectsforks/morphit:<upstream-tag>
ghcr.io/nekosuneprojectsforks/morphit:latest
```

Architectures:

- `linux/amd64`
- `linux/arm64`

The same image contains the released Morphit source/build artifacts and can be started in different modes:

```bash
# Static Morphit web frontend on http://localhost:8080
docker run --rm -p 8080:8080 ghcr.io/nekosuneprojectsforks/morphit:latest web

# Backend services (supply the Morphit environment/config they require)
docker run --rm ghcr.io/nekosuneprojectsforks/morphit:latest indexer
docker run --rm ghcr.io/nekosuneprojectsforks/morphit:latest relay

# MCP server
docker run --rm -i ghcr.io/nekosuneprojectsforks/morphit:latest mcp

# Operator CLI
docker run --rm -it ghcr.io/nekosuneprojectsforks/morphit:latest ops
```

`indexer`, `relay`, and the operator tooling still need the database, secrets, environment variables, and persistent paths documented by upstream Morphit. This wrapper intentionally does not invent replacement defaults for those security-sensitive settings.

## Docker Compose

A production-oriented Compose file is included for the Morphit web frontend behind Nginx Proxy Manager:

```bash
cp .env.example .env
```

Set `NPM_NETWORK` in `.env` to a Docker network already attached to your Nginx Proxy Manager container, then run:

```bash
docker compose pull
docker compose up -d
```

The Compose deployment deliberately does **not** publish Morphit's port `8080` on the Docker host. Nginx Proxy Manager reaches the `morphit` network alias directly over the shared Docker network.

The Compose service also runs read-only with dropped Linux capabilities, `no-new-privileges`, a temporary `/tmp`, and a built-in health check.

For the complete Cloudflare and Nginx Proxy Manager setup, including DNS, TLS, proxy-host settings, Full (strict) mode, firewall guidance, and troubleshooting, see:

**[docs/CLOUDFLARE-NPM.md](docs/CLOUDFLARE-NPM.md)**

## Release-only update policy

`.github/workflows/upstream-release.yml` checks the official Agorise Forgejo releases every 6 hours and can also be run manually from the Actions tab.

The workflow:

1. asks the official Forgejo API for the newest published Morphit release (drafts are ignored; prereleases count as releases),
2. compares the tag with `.upstream-release`,
3. exits before QEMU/Docker build setup when the tag is unchanged,
4. when a release is new, passes that exact tag into the Docker build as `MORPHIT_TAG`,
5. the Dockerfile itself downloads and SHA-256 verifies that official Agorise release,
6. Buildx builds one image for AMD64 + ARM64 and pushes both the upstream release tag and `latest`,
7. the workflow records the tag in `.upstream-release` **only after** the image push succeeds.

There is deliberately no `push` build trigger and no polling of upstream commits, so ordinary source commits do not create Docker images.

## Build locally

Build the latest published official Morphit release for your current architecture:

```bash
docker build -t morphit:local .
```

The Dockerfile defaults `MORPHIT_TAG` to `latest`, resolves the newest published release from Agorise, downloads it and verifies it inside the build.

Build a specific upstream release instead:

```bash
docker build \
  --build-arg MORPHIT_TAG=v1.2.3 \
  -t morphit:v1.2.3 \
  .
```

For a multi-platform build:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg MORPHIT_TAG=v1.2.3 \
  -t your-registry/morphit:v1.2.3 \
  --push .
```

You can still use the helper directly to inspect upstream without building an image:

```bash
python3 scripts/fetch-release.py --latest-tag
```

## Upstream provenance

Morphit source, release artifacts, and its AGPL-3.0 license remain owned/licensed by the upstream project and contributors. The Docker image keeps the verified upstream release source tree and license under `/app`.

Upstream repository: https://git.agorise.net/agorise/morphit
