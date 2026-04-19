#!/usr/bin/env bash

set -u -o pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

tasks=(
    task01-check.sh
    task02-check.sh
    task03-check.sh
    task04-check.sh
    task05-check.sh
    task06-check.sh
    task07-check.sh
)

passed=0
failed=0

for task in "${tasks[@]}"; do
    task_path="$script_dir/$task"

    if [ ! -x "$task_path" ]; then
        chmod +x "$task_path" 2>/dev/null || true
    fi

    if [ ! -f "$task_path" ]; then
        printf '[PUUDU] %s\n' "$task"
        failed=$((failed + 1))
        continue
    fi

    printf '\n=== %s ===\n' "$task"
    if "$task_path"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
done

printf '\nKokkuvote: %d korras, %d ebaonnestus\n' "$passed" "$failed"

if [ "$failed" -eq 0 ]; then
    exit 0
fi

exit 1
