#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_FILE="${SCRIPT_DIR}/server.conf"
DEFAULT_SERVER="http://10.10.10.139/skripti_kontroll/api/db-submit.php"

resolve_server_url() {
    if [ -n "${SERVER_URL:-}" ]; then
        echo "$SERVER_URL"
        return
    fi

    if [ -f "$SERVER_CONFIG_FILE" ]; then
        local config_value
        config_value="$(grep -E '^[[:space:]]*[^#[:space:]]' "$SERVER_CONFIG_FILE" | head -n 1 | tr -d '\r' || true)"
        if [ -n "$config_value" ]; then
            echo "$config_value"
            return
        fi
    fi

    echo "$DEFAULT_SERVER"
}

SERVER="$(resolve_server_url)"
HOST="$(hostname)"
OS="$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2 2>/dev/null || uname -s)"

send_result() {
    local task="$1"

    curl -fsS --max-time 10 -X POST "$SERVER" \
        -o /dev/null \
        -d "hostname=$HOST" \
        -d "task=$task" \
        -d "os=$OS" || {
            echo "ERROR: Tulemust ei saanud saata URL-ile: $SERVER"
            echo "Vihje: sea SERVER_URL voi muuda faili $(basename "$SERVER_CONFIG_FILE")"
            return 1
        }

    echo "Result sent for task $task"
}
