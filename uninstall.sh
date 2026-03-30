#!/usr/bin/env bash
# ag-math-render — Uninstall Script
# Removes the math rendering patch from Antigravity.
#
# Usage: bash uninstall.sh [/path/to/Antigravity.app]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

APP_PATH="${1:-/Applications/Antigravity.app}"
RESOURCES="$APP_PATH/Contents/Resources/app"
WORKBENCH_DIR="$RESOURCES/out/vs/code/electron-browser/workbench"

HTML_FILES=(
    "$WORKBENCH_DIR/workbench.html"
    "$WORKBENCH_DIR/workbench-jetski-agent.html"
)

echo -e "${GREEN}ag-math-render uninstaller${NC}"
echo ""

# Remove injected script tags from all HTML files
echo "  [1/3] Removing script tags..."
for html_file in "${HTML_FILES[@]}"; do
    fname=$(basename "$html_file")
    echo -n "         $fname... "
    if [ ! -f "$html_file" ]; then
        echo -e "${YELLOW}not found, skipping${NC}"
        continue
    fi
    if grep -q "ag-math-render" "$html_file"; then
        sed -i '' '/ag-math-render/d' "$html_file"
        echo -e "${GREEN}done${NC}"
    else
        echo -e "${YELLOW}not patched${NC}"
    fi
done

# Remove math-patch.js
echo -n "  [2/3] Removing math-patch.js... "
if [ -f "$WORKBENCH_DIR/math-patch.js" ]; then
    rm "$WORKBENCH_DIR/math-patch.js"
    echo -e "${GREEN}done${NC}"
else
    echo -e "${YELLOW}not found${NC}"
fi

# Remove katex directory
echo -n "  [3/3] Removing katex/... "
if [ -d "$WORKBENCH_DIR/katex" ]; then
    rm -rf "$WORKBENCH_DIR/katex"
    echo -e "${GREEN}done${NC}"
else
    echo -e "${YELLOW}not found${NC}"
fi

echo ""
echo -e "${GREEN}✓ Uninstall complete!${NC}"
echo "  Restart Antigravity to apply changes."
