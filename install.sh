#!/usr/bin/env bash
# ag-math-render — Install Script
# Patches Antigravity AI IDE to render LaTeX math in chat.
#
# Usage: bash install.sh [/path/to/Antigravity.app]
#
# What this script does:
#   1. Copies math-patch.js + KaTeX into the Antigravity app bundle
#   2. Wraps katex.min.js with AMD suspension (so it sets window.katex)
#   3. Injects static <link> and <script> tags into HTML files
#   4. Removes checksums from product.json
#
# Idempotent: safe to run multiple times.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Locate Antigravity ──────────────────────────────────────────

APP_PATH="${1:-/Applications/Antigravity.app}"
RESOURCES="$APP_PATH/Contents/Resources/app"
WORKBENCH_DIR="$RESOURCES/out/vs/code/electron-browser/workbench"
PRODUCT_JSON="$RESOURCES/product.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload"

# HTML files to patch (editor sidebar + Agent Manager window)
HTML_FILES=(
    "$WORKBENCH_DIR/workbench.html"
    "$WORKBENCH_DIR/workbench-jetski-agent.html"
)

# Checksum keys to remove from product.json
CHECKSUM_KEYS=(
    "vs/code/electron-browser/workbench/workbench.html"
    "vs/code/electron-browser/workbench/workbench-jetski-agent.html"
)

# ── Preflight Checks ───────────────────────────────────────────

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}✗ Antigravity not found at: $APP_PATH${NC}"
    echo "  Usage: bash install.sh /path/to/Antigravity.app"
    exit 1
fi

if [ ! -d "$PAYLOAD_DIR" ]; then
    echo -e "${RED}✗ payload/ directory not found. Run from the project root.${NC}"
    exit 1
fi

echo -e "${GREEN}ag-math-render installer${NC}"
echo "  Antigravity: $APP_PATH"
echo ""

# ── Step 1: Copy payload ───────────────────────────────────────

DST_JS="$WORKBENCH_DIR/math-patch.js"
DST_KATEX="$WORKBENCH_DIR/katex"

echo -n "  [1/4] Copying payload... "
cp "$PAYLOAD_DIR/math-patch.js" "$DST_JS"
rm -rf "$DST_KATEX"
cp -r "$PAYLOAD_DIR/katex" "$DST_KATEX"
echo -e "${GREEN}done${NC}"

# ── Step 2: Wrap KaTeX with AMD suspension ─────────────────────
# Antigravity uses AMD loader; KaTeX detects define.amd and tries
# to register as AMD module instead of setting window.katex.
# We wrap katex.min.js to temporarily hide define.amd.

echo -n "  [2/4] Wrapping KaTeX for AMD compatibility... "
KATEX_JS="$DST_KATEX/katex.min.js"
KATEX_ORIG="$DST_KATEX/katex.min.original.js"

# Save original if not already saved
if [ ! -f "$KATEX_ORIG" ]; then
    cp "$KATEX_JS" "$KATEX_ORIG"
fi

# Create wrapped version
{
    echo '/* ag-math-render: AMD suspension wrapper */'
    echo '(function(){var _d=window.define;if(_d&&_d.amd){try{window.define=undefined}catch(e){}}'
    cat "$KATEX_ORIG"
    echo ';if(typeof _d!=="undefined"){try{window.define=_d}catch(e){}}})();'
} > "$KATEX_JS"
echo -e "${GREEN}done${NC}"

# ── Step 3: Inject tags into HTML files ────────────────────────
# We inject STATIC <link> and <script> tags. These are parsed by
# the HTML parser, which is NOT subject to Trusted Types CSP.
# This completely avoids the TrustedScriptURL error.

MARKER="ag-math-render"
# The injection block: CSS + KaTeX JS + our patch JS
INJECT_BLOCK="<!-- ${MARKER} --><link rel=\"stylesheet\" href=\"./katex/katex.min.css\"><script src=\"./katex/katex.min.js\"></script><script src=\"./math-patch.js\" type=\"module\"></script>"

echo "  [3/4] Patching HTML files..."

for html_file in "${HTML_FILES[@]}"; do
    fname=$(basename "$html_file")
    echo -n "         $fname... "

    if [ ! -f "$html_file" ]; then
        echo -e "${YELLOW}not found, skipping${NC}"
        continue
    fi

    if grep -q "$MARKER" "$html_file"; then
        # Already patched — remove old injection and re-inject (idempotent update)
        sed -i '' "/${MARKER}/d" "$html_file"
    fi

    if grep -q '</html>' "$html_file"; then
        sed -i '' "s|</html>|${INJECT_BLOCK}\n</html>|" "$html_file"
        echo -e "${GREEN}done${NC}"
    else
        echo -e "${RED}FAILED — </html> not found${NC}"
    fi
done

# ── Step 4: Clear checksums ────────────────────────────────────

echo -n "  [4/4] Clearing checksums... "

if [ -f "$PRODUCT_JSON" ]; then
    python3 -c "
import json, sys
path = sys.argv[1]
keys = sys.argv[2:]
with open(path) as f:
    data = json.load(f)
checksums = data.get('checksums', {})
removed = 0
for key in keys:
    if key in checksums:
        del checksums[key]
        removed += 1
if removed > 0:
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f'removed {removed} checksum(s)')
else:
    print('already clean')
" "$PRODUCT_JSON" "${CHECKSUM_KEYS[@]}"
else
    echo -e "${YELLOW}product.json not found, skipping${NC}"
fi

# ── Done ───────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo "  Restart Antigravity to see math rendering in chat."
echo "  Works in both Editor sidebar and Agent Manager window."
echo ""
echo "  To uninstall: bash $(dirname "$0")/uninstall.sh"
