#!/usr/bin/env bash
# Checks out paint-by-number at the pinned commit into .deps/paint-by-number (not committed), the
# local package that Package.swift and the app's Xcode project take PaintCore from: only that
# commit, fetched shallow, since SwiftPM would otherwise clone the whole repository with every ref
# (its CI report refs make that many gigabytes). App/Ravenna was copied from this commit's
# App/PaintByNumber (CLAUDE.md). Move the pin on purpose, and say why in the commit. Idempotent.
#   tools/paintcore.sh && swift test
set -euo pipefail
REV=f1024441199d1634e7a8c35012fe6af2f9973648
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.deps/paint-by-number"
if [[ "$(git -C "$DEST" rev-parse -q --verify HEAD 2>/dev/null)" != "$REV" ]]; then
  rm -rf "$DEST"; mkdir -p "$DEST"
  git -C "$DEST" init -q
  git -C "$DEST" fetch -q --depth 1 https://github.com/pbordjadze/paint-by-number "$REV"
  git -C "$DEST" -c advice.detachedHead=false checkout -q FETCH_HEAD
fi
echo "PaintCore $REV in $DEST"
