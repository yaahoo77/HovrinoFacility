#!/bin/bash
# Builds the Lovable website (TanStack Start) as plain files and puts them into site/,
# so install.sh can serve them with Apache next to the game.
#   bash tools/build-site.sh /path/to/your-lovable-repo
# Needs Node.js 20+ (or bun). Your Lovable repository itself is not changed.
# Audio/images uploaded in Lovable come from site-media/ (see the end of this script).
set -euo pipefail
GAME=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:?usage: bash tools/build-site.sh /path/to/your-lovable-repo}
SRC=$(cd "$SRC" && pwd)
[ -f "$SRC/package.json" ] || { echo "No package.json in $SRC" >&2; exit 1; }

cd "$SRC"
# Build as a single-page app (one HTML file + JavaScript) instead of Lovable's Cloudflare server.
cat > vite.phonegame.config.ts <<'CFG'
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
export default defineConfig({
  tanstackStart: { server: { entry: "server" }, spa: { enabled: true } },
  nitro: false,
});
CFG
trap 'rm -f "$SRC/vite.phonegame.config.ts"' EXIT

if command -v bun >/dev/null; then bun install; else npm install --no-audit --no-fund; fi
rm -rf dist
npx vite build --config vite.phonegame.config.ts
[ -f dist/client/_shell.html ] || { echo "Build did not produce dist/client/_shell.html" >&2; exit 1; }

find "$GAME/site" -mindepth 1 ! -name README.md -delete
cp -r dist/client/. "$GAME/site/"
cp "$GAME/site/_shell.html" "$GAME/site/index.html"   # Apache serves index.html for every page

# Files uploaded in Lovable (audio, images...) are not in the repository: Lovable keeps them on its own
# server and the site points to them as /__l5e/assets-v1/... Put a copy at that same path in site/,
# taken from site-media/ (by original file name) or, with LOVABLE_SITE=https://your-site.lovable.app,
# downloaded from your published Lovable site (and kept in site-media/ for next time).
MISSING=0
for meta in "$SRC"/src/assets/*.asset.json; do
  [ -e "$meta" ] || continue
  url=$(node -p 'require(process.argv[1]).url' "$meta")
  name=$(node -p 'require(process.argv[1]).original_filename' "$meta")
  dest="$GAME/site$url"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$GAME/site-media/$name" ]; then
    cp "$GAME/site-media/$name" "$dest"
  elif [ -n "${LOVABLE_SITE:-}" ] && curl -fsSL -o "$dest" "${LOVABLE_SITE%/}$url"; then
    mkdir -p "$GAME/site-media"; cp "$dest" "$GAME/site-media/$name"
    echo "Downloaded $name from $LOVABLE_SITE into site-media/"
  else
    rm -f "$dest"; MISSING=1
    echo "MISSING: $name (put it into site-media/, or run again with LOVABLE_SITE=https://your-site.lovable.app)" >&2
  fi
done
[ "$MISSING" = 0 ] || echo "The website works, but the files marked MISSING won't play or show until you add them." >&2
echo "Website built into $GAME/site ($(find "$GAME/site" -type f | wc -l) files). Now run: sudo bash install.sh"
