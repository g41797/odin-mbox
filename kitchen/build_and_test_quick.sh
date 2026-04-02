#!/usr/bin/env bash


set -euo pipefail

GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

OPTS=(none)

BUILDS=(
    .
    examples/block1
    examples/block2
    examples/block3
    examples/block4
)

TESTS=(
    tests/block1
    tests/block2
    tests/block3
    tests/block4
)

echo "${BLUE}Starting flat local CI (quick)...${NC}"

if ! command -v odin >/dev/null 2>&1; then
    echo "Error: odin compiler not found in PATH"
    exit 1
fi

for opt in "${OPTS[@]}"; do
    echo
    echo "${BLUE}--- opt: ${opt} ---${NC}"

    for path in "${BUILDS[@]}"; do
        if [ -d "./${path}" ] && [ -n "$(find ./${path} -maxdepth 1 -name '*.odin' -size +0c 2>/dev/null | head -1)" ]; then
            echo "  build ${path}..."
            if [ "${opt}" = "none" ]; then
                odin build ./${path}/ -build-mode:lib -vet -strict-style -o:none -debug
            else
                odin build ./${path}/ -build-mode:lib -vet -strict-style -o:"${opt}"
            fi
        fi
    done

    for path in "${TESTS[@]}"; do
        if [ -d "./${path}" ] && [ -n "$(find ./${path} -name '*.odin' -size +0c 2>/dev/null | head -1)" ]; then
            echo "  test ${path}/..."
            if [ "${opt}" = "none" ]; then
                odin test ./${path}/ -vet -strict-style -disallow-do -o:none -debug
            else
                odin test ./${path}/ -vet -strict-style -disallow-do -o:"${opt}"
            fi
        fi
    done

    echo "${GREEN}  pass: ${opt}${NC}"
done


echo
echo "${GREEN}ALL CHECKS PASSED${NC}"
