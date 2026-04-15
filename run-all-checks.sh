#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

for script in task*-check.sh; do
    echo
    echo "=== Running $script ==="
    bash "$script"
done
