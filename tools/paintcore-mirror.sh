#!/usr/bin/env bash
# Points SwiftPM at a slim local copy of paint-by-number: only the pinned PaintCore commit,
# fetched shallow. SwiftPM otherwise clones the whole repository with every ref (its CI report
# refs make that many gigabytes). Package.swift keeps the real URL and the revision pin; the
# mirror lives in .swiftpm/configuration/mirrors.json, which is not committed. Idempotent.
#   tools/paintcore-mirror.sh && swift test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL=https://github.com/pbordjadze/paint-by-number
REV="$(sed -n 's/.*revision: "\([0-9a-f]\{40\}\)".*/\1/p' "$ROOT/Package.swift")"
[[ -n "$REV" ]] || { echo "no PaintCore revision in Package.swift" >&2; exit 1; }
MIRROR="$ROOT/.build/mirror/paint-by-number.git"
if ! git -C "$MIRROR" cat-file -e "$REV^{commit}" 2>/dev/null; then
  rm -rf "$MIRROR"; mkdir -p "$(dirname "$MIRROR")"
  git init -q --bare "$MIRROR"
  git -C "$MIRROR" fetch -q --depth 1 "$URL" "$REV:refs/heads/main"
fi
cd "$ROOT"
swift package config set-mirror --original "$URL" --mirror "file://$MIRROR"
echo "PaintCore $REV from $MIRROR"
