# morphit-docker

Unofficial multi-architecture Docker wrapper for [Agorise Morphit](https://git.agorise.net/agorise/morphit).

This repository does **not** mirror Morphit's `main` branch and does not rebuild on every upstream commit. It follows published Morphit releases only.

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

## Release-only update policy

`.github/workflows/upstream-release.yml` checks Forgejo every 6 hours and can also be run manually from the Actions tab.

The workflow:

1. asks the Forgejo API for the newest published Morphit release (drafts are ignored; prereleases count as releases),
2. compares the tag with `.upstream-release`,
3. exits before QEMU/npm/Docker setup when the tag is unchanged,
4. when a release is new, downloads the canonical release `.tar.gz` and matching `.sha256` asset,
5. verifies the SHA-256 before extracting anything,
6. builds one Docker image for AMD64 + ARM64 and pushes both the upstream release tag and `latest`,
7. records the tag in `.upstream-release` **only after** the image push succeeds.

There is deliberately no `push` build trigger and no polling of upstream commits, so ordinary source commits do not create Docker images.

## Fetch a release locally

Check the latest upstream release without downloading it:

```bash
python3 scripts/fetch-release.py --latest-tag
```

Download and verify the latest release into `upstream/`:

```bash
python3 scripts/fetch-release.py --output upstream
```

Or fetch a particular release:

```bash
python3 scripts/fetch-release.py --tag v1.2.3 --output upstream
```

Then build for the machine you are currently on:

```bash
docker build -t morphit:local .
```

For a local multi-platform build with Buildx:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t your-registry/morphit:tag \
  --push .
```

## Upstream provenance

Morphit source, release artifacts, and its AGPL-3.0 license remain owned/licensed by the upstream project and contributors. The Docker image keeps the upstream source tree and license under `/app`.

Upstream repository: https://git.agorise.net/agorise/morphit
