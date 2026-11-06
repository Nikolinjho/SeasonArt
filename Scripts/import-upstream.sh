#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -e Sources/SeasonArt || -L Sources/SeasonArt ]]; then
  printf '%s\n' 'Import refused: Sources/SeasonArt already exists.' >&2
  exit 1
fi

SEASONART_UPSTREAM_DIR="$(mktemp -d)"
trap 'rm -rf "$SEASONART_UPSTREAM_DIR"' EXIT
SEASONART_UPSTREAM_SHA=013f36782e5c6d017725aeb4b2173ae329bf0c6e
git -C "$SEASONART_UPSTREAM_DIR" init --quiet
git -C "$SEASONART_UPSTREAM_DIR" fetch --quiet --depth=1 \
  https://github.com/mbezruchko/Snowhush.git "$SEASONART_UPSTREAM_SHA"
test "$(git -C "$SEASONART_UPSTREAM_DIR" rev-parse FETCH_HEAD)" = "$SEASONART_UPSTREAM_SHA"
git -C "$SEASONART_UPSTREAM_DIR" archive FETCH_HEAD Sources/Snowhush Resources/Info.plist LICENSE \
  | tar -xf - -C "$SEASONART_UPSTREAM_DIR"
mkdir -p Sources Resources
ditto "$SEASONART_UPSTREAM_DIR/Sources/Snowhush" Sources/SeasonArt
cp "$SEASONART_UPSTREAM_DIR/Resources/Info.plist" Resources/Info.plist
cp "$SEASONART_UPSTREAM_DIR/LICENSE" LICENSE
printf '%s\n' '{"repository":"https://github.com/mbezruchko/Snowhush","commit":"013f36782e5c6d017725aeb4b2173ae329bf0c6e","license":"PolyForm-Noncommercial-1.0.0","importedSubtree":"Sources/Snowhush"}' > UPSTREAM.json
printf 'Imported Snowhush commit %s.\n' "$SEASONART_UPSTREAM_SHA"
