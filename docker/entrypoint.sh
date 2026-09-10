#!/bin/sh
set -eu

cd /app

run_workspace() {
  workspace="$1"
  shift || true

  if node -e "const p=require('./${workspace}/package.json'); process.exit(p.scripts && p.scripts.start ? 0 : 1)"; then
    exec npm run start --workspace="${workspace}" -- "$@"
  fi

  for candidate in \
    "${workspace}/src/index.ts" \
    "${workspace}/src/server.ts" \
    "${workspace}/src/main.ts"
  do
    if [ -f "$candidate" ]; then
      exec ./node_modules/.bin/tsx "$candidate" "$@"
    fi
  done

  echo "No start script or known TypeScript entrypoint found for ${workspace}." >&2
  exit 64
}

mode="${1:-web}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$mode" in
  web)
    if [ ! -f /app/apps/web/build/index.html ]; then
      echo "Morphit web build is missing: /app/apps/web/build/index.html" >&2
      exit 66
    fi
    exec nginx -c /opt/morphit-docker/nginx.conf -g 'daemon off;'
    ;;

  indexer)
    run_workspace apps/indexer "$@"
    ;;

  relay)
    run_workspace apps/relay "$@"
    ;;

  mcp)
    if [ -f /app/apps/mcp-server/dist/main.js ]; then
      exec node /app/apps/mcp-server/dist/main.js "$@"
    fi
    run_workspace apps/mcp-server "$@"
    ;;

  matrix-bot)
    run_workspace apps/matrix-bot "$@"
    ;;

  ops)
    if [ -x /app/node_modules/.bin/morphit-ops ]; then
      exec /app/node_modules/.bin/morphit-ops "$@"
    fi
    if [ -f /app/apps/ops-cli/bin/morphit-ops.mjs ]; then
      exec node /app/apps/ops-cli/bin/morphit-ops.mjs "$@"
    fi
    echo "Morphit operator CLI was not found in this release." >&2
    exit 66
    ;;

  shell)
    exec /bin/sh "$@"
    ;;

  *)
    exec "$mode" "$@"
    ;;
esac
