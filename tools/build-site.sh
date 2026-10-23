#!/bin/bash
# Builds the Lovable website (TanStack Start) as plain files and puts them into site/,
# so install.sh can serve them with Apache next to the game.
#   bash tools/build-site.sh /path/to/your-lovable-repo
# Needs Node.js 20+ (or bun). Your Lovable repository itself is not changed.
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
echo "Website built into $GAME/site ($(find "$GAME/site" -type f | wc -l) files). Now run: sudo bash install.sh"
