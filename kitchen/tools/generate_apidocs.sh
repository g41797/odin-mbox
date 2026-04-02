#!/usr/bin/env bash

set -ex

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

TOOLS_DIR=$(realpath "$(dirname "$0")")
KITCHEN_DIR=$(realpath "$TOOLS_DIR/..")
ROOT_DIR=$(realpath "$KITCHEN_DIR/..")
APIDOCS_DIR="$KITCHEN_DIR/docs/apidocs"

cd "$ROOT_DIR"

rm -rf "$APIDOCS_DIR"
mkdir -p "$APIDOCS_DIR"

# Generate intermediate binary format
odin doc . ./examples/block1 ./examples/block2 ./examples/block3 ./examples/block4 \
    -all-packages -doc-format -out:matryoshka.odin-doc

# Create config with absolute paths substituted
sed "s|PROJECT_ROOT|$ROOT_DIR|g" "$TOOLS_DIR/odin-doc.json" > "$APIDOCS_DIR/odin-doc.json"

cd "$APIDOCS_DIR"

# Render to HTML
LD_LIBRARY_PATH="$TOOLS_DIR" "$TOOLS_DIR/odin-doc" "$ROOT_DIR/matryoshka.odin-doc" ./odin-doc.json

# Post-process: remove "Generation Information" sections and TOC links
find . -name "index.html" -exec sed -i '/<h2 id="pkg-generation-information">/,/<p>Generated with .*<\/p>/d' {} +
find . -name "index.html" -exec sed -i '/<li><a href="#pkg-generation-information">/d' {} +

# Post-process: Make all links and assets relative.
# odin-doc emits absolute hrefs ("/matryoshka/...") which break when served from a
# subdirectory. Replace with relative prefixes based on nesting depth.
#
# Actual generated structure:
#   index.html                               (depth 0)
#   matryoshka/index.html                    (depth 1)
#   matryoshka/examples/block1/index.html    (depth 3)
#   matryoshka/examples/block2/index.html    (depth 3)
#   matryoshka/examples/block3/index.html    (depth 3)
#   matryoshka/examples/block4/index.html    (depth 3)

# Depth 0 — root index.html
sed -i 's|href="/\([^/]\)|href="./\1|g' index.html
sed -i 's|src="/\([^/]\)|src="./\1|g' index.html

# All other index.html files: compute depth by counting path separators
find . -name "index.html" ! -path "./index.html" | while read -r f; do
    # Count depth: number of "/" in path minus leading "./"
    depth=$(echo "$f" | tr -cd '/' | wc -c)
    # depth includes the leading "./" so actual depth = depth - 1
    actual_depth=$(( depth - 1 ))
    prefix=""
    for _ in $(seq 1 "$actual_depth"); do
        prefix="../$prefix"
    done
    sed -i "s|href=\"/\([^/]\)|href=\"${prefix}\1|g" "$f"
    sed -i "s|src=\"/\([^/]\)|src=\"${prefix}\1|g" "$f"
done

# Fix blank root package nav link — odin-doc emits an empty <a> when the
# collection name matches the root package name. Fill in the package name.
find . -name "index.html" -exec sed -i \
    's|<a \([^>]*\)href="\([^"]*\)matryoshka/"\([^>]*\)></a>|<a \1href="\2matryoshka/"\3>matryoshka</a>|g' {} +

# pkg-data.js contains absolute paths used by search.js for navigation
# (e.g. "path": "/matryoshka/"). sed does not process .js files, so those
# paths point to the server root instead of /apidocs/. Prefix them here.
sed -i 's|"path": "/|"path": "/apidocs/|g' "$APIDOCS_DIR/pkg-data.js"

# In matryoshka/index.html, sub-package links are emitted as ../matryoshka/examples/X.
# When the server delivers index.html at a URL without a trailing slash
# (e.g. /apidocs/matryoshka instead of /apidocs/matryoshka/), the browser
# resolves ../matryoshka/ relative to the wrong base and produces a double-
# matryoshka path (/apidocs/matryoshka/matryoshka/examples/X → 404).
# Simplify those links to ./examples/X — same destination, no ambiguity.
sed -i 's|href="\.\./matryoshka/examples/|href="./examples/|g' matryoshka/index.html

# Copy shared assets into every package subdirectory so the browser finds
# them regardless of which relative path a cached HTML page requests them from.
find . -mindepth 2 -name "index.html" | while read -r f; do
    dir=$(dirname "$f")
    cp favicon.svg  "$dir/favicon.svg"
    cp style.css    "$dir/style.css"
    cp pkg-data.js  "$dir/pkg-data.js"
    cp search.js    "$dir/search.js"
done

# Cache-busting: append ?v=<timestamp> to all shared asset references so
# browsers never serve stale files after apidocs regeneration.
VER=$(date +%Y%m%d%H%M%S)
find . -name "index.html" -exec sed -i \
    -e "s|favicon\.svg\"|favicon.svg?v=${VER}\"|g" \
    -e "s|style\.css\"|style.css?v=${VER}\"|g" \
    -e "s|pkg-data\.js\"|pkg-data.js?v=${VER}\"|g" \
    -e "s|search\.js\"|search.js?v=${VER}\"|g" {} +

cd "$ROOT_DIR"
rm -f matryoshka.odin-doc
