#!/usr/bin/env bash

set -e

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

SCRIPT_DIR=$(realpath "$(dirname "$0")")
ROOT_DIR=$(realpath "$SCRIPT_DIR/..")
APIDOCS_DIR="$SCRIPT_DIR/docs/apidocs"

# Ensure odin-doc renderer is built
if [ ! -x "$ROOT_DIR/tools/odin-doc" ]; then
    echo "odin-doc not found, building..."
    bash "$ROOT_DIR/tools/get_odin_doc.sh"
fi

# Generate standalone odin-doc HTML site into docs/build/
cd "$ROOT_DIR"
bash docs/generate.sh

# Copy into docs/apidocs/ so mkdocs serves it (serve + build)
rm -rf "$APIDOCS_DIR"
cp -r "$ROOT_DIR/docs/build" "$APIDOCS_DIR"

# Build mkdocs site
cd "$SCRIPT_DIR"
mkdocs build
