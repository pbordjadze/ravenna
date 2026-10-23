#!/usr/bin/env bash
# Runs a Swift toolchain command for the package inside the swift:6.2 Docker image (as
# paint-by-number's tools/swift.sh does), for machines without a Swift toolchain.
#   tools/swift.sh build
#   tools/swift.sh test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! docker info >/dev/null 2>&1; then
  (dockerd >/tmp/dockerd.log 2>&1 &)
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
exec docker run --rm -v "$ROOT:$ROOT" -w "$ROOT" swift:6.2-noble swift "$@"
