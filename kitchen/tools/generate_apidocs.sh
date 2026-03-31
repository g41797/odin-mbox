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
odin doc . ./examples/layer1 ./examples/layer2 ./examples/layer3 ./examples/layer4 \
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
#   matryoshka/examples/layer1/index.html    (depth 3)
#   matryoshka/examples/layer2/index.html    (depth 3)
#   matryoshka/examples/layer3/index.html    (depth 3)
#   matryoshka/examples/layer4/index.html    (depth 3)

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

cd "$ROOT_DIR"
rm -f matryoshka.odin-doc
