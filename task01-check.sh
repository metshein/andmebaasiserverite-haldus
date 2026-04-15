#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

echo "1) Checking MariaDB install..."
if ! command -v mariadb >/dev/null 2>&1; then
    echo "FAIL: mariadb command not found."
    exit 1
fi
MARIADB_VERSION="$(mariadb --version 2>/dev/null || true)"
if [[ -z "$MARIADB_VERSION" ]]; then
    echo "FAIL: could not read MariaDB version."
    exit 1
fi
echo "MariaDB: $MARIADB_VERSION"

SERVICE_ENABLED="unknown"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled mariadb >/dev/null 2>&1 || systemctl is-enabled mysql >/dev/null 2>&1; then
        SERVICE_ENABLED="enabled"
    else
        SERVICE_ENABLED="not-enabled"
    fi
fi
echo "Autostart: $SERVICE_ENABLED"
echo "OK"

run_sql() {
    local sql="$1"
    if sudo -n true >/dev/null 2>&1; then
        sudo mariadb -N -B -u root -e "$sql" 2>/dev/null && return 0
    fi
    mariadb -N -B -u root -e "$sql" 2>/dev/null
}

echo "2) Checking baseline security setup..."
anon_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='';" || echo "ERR")"
testdb_count="$(run_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='test';" || echo "ERR")"
root_remote_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='root' AND host NOT IN ('localhost','127.0.0.1','::1');" || echo "ERR")"
root_plugin="$(run_sql "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost' LIMIT 1;" || echo "ERR")"

if [[ "$anon_count" == "ERR" || "$testdb_count" == "ERR" || "$root_remote_count" == "ERR" || "$root_plugin" == "ERR" ]]; then
    echo "FAIL: SQL checks failed (try sudo mariadb -u root)."
    exit 1
fi

echo "root plugin: $root_plugin"
echo "anonymous users: $anon_count"
echo "test DB count: $testdb_count"
echo "root remote logins: $root_remote_count"

if [[ "$anon_count" -ne 0 ]]; then
    echo "FAIL: anonymous users still exist."
    exit 1
fi
if [[ "$testdb_count" -ne 0 ]]; then
    echo "FAIL: test database still exists."
    exit 1
fi
if [[ "$root_remote_count" -ne 0 ]]; then
    echo "FAIL: root remote login is not restricted."
    exit 1
fi
echo "OK"

echo "3) Checking network hardening config..."
CNF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [[ ! -f "$CNF_FILE" ]]; then
    echo "FAIL: config file not found: $CNF_FILE"
    exit 1
fi

if ! grep -Eq '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*127\.0\.0\.1' "$CNF_FILE"; then
    echo "FAIL: bind-address = 127.0.0.1 missing."
    exit 1
fi
if ! grep -Eq '^[[:space:]]*local-infile[[:space:]]*=[[:space:]]*0' "$CNF_FILE"; then
    echo "FAIL: local-infile = 0 missing."
    exit 1
fi
if ! grep -Eq '^[[:space:]]*skip-name-resolve([[:space:]]*=[[:space:]]*1)?' "$CNF_FILE"; then
    echo "FAIL: skip-name-resolve missing."
    exit 1
fi
echo "OK"

echo "4) Checking service state and bind address..."
service_ok=0
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        service_ok=1
    fi
fi
if [[ "$service_ok" -ne 1 ]]; then
    echo "FAIL: MariaDB service is not active."
    exit 1
fi

PORT_LINE="$(ss -tlnp 2>/dev/null | grep -E '(:3306\\b|mariadbd|mysqld)' | head -n1 || true)"
if [[ -n "$PORT_LINE" ]]; then
    echo "Port check: 3306/process visible"
else
    echo "Port check: 3306 not visible (possible with skip-networking=1)"
fi

BIND_ADDR="$(run_sql "SHOW VARIABLES LIKE 'bind_address';" | awk '{print $2}' | head -n1 || true)"
if [[ -z "$BIND_ADDR" ]]; then
    echo "FAIL: could not read bind_address."
    exit 1
fi
echo "bind_address: $BIND_ADDR"
echo "OK"

echo "Task 1 passed."
send_result 1
