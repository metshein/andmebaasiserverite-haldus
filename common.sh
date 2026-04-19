#!/usr/bin/env bash

set -euo pipefail

SERVER="${SERVER_URL:-https://metshein.com/skripti_kontroll/api/db-submit.php}"
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
            echo "Vihje: sea SERVER_URL keskkonnamuutuja"
            return 1
        }

    echo "Result sent for task $task"
}
