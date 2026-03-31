#!/usr/bin/env bash
# build_site.sh
# Generates odin-doc HTML then builds the full MkDocs static site.
# Output goes to kitchen/output/
# Run from anywhere. Linux only.

set -e

TOOLS_DIR=$(dirname "$(readlink -f "$0")")
KITCHEN_DIR=$(dirname "$TOOLS_DIR")
ROOT_DIR=$(dirname "$KITCHEN_DIR")

if [ ! -f "$TOOLS_DIR/odin-doc" ]; then
    echo "Error: odin-doc binary not found in $TOOLS_DIR"
    echo "Run: bash kitchen/tools/get_odin_doc.sh"
    exit 1
fi

if ! command -v mkdocs >/dev/null 2>&1; then
    echo "Error: mkdocs not found in PATH"
    echo "Install: pip install mkdocs-material"
    exit 1
fi

echo "--- Generating API docs ---"
cd "$ROOT_DIR"
bash "$TOOLS_DIR/generate_apidocs.sh"

echo "--- Building MkDocs site ---"
cd "$KITCHEN_DIR"
mkdocs build -f mkdocs.yml

echo "--- Done ---"
echo "Output: $KITCHEN_DIR/output/"
