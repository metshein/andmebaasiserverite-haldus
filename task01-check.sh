#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

DOC_FILE=""
for candidate in "dokumentatsioon.md" "dokumentatsioon.txt" "documentation.md" "documentation.txt" "README.md"; do
    if [[ -f "$candidate" ]]; then
        DOC_FILE="$candidate"
        break
    fi
done

if [[ -z "$DOC_FILE" ]]; then
    echo "FAIL: Dokumentatsiooni faili ei leitud (nt README.md / dokumentatsioon.md / documentation.md)."
    exit 1
fi

DOC_CONTENT="$(tr '[:upper:]' '[:lower:]' < "$DOC_FILE")"

has_any() {
    local text="$1"
    shift
    local needle
    for needle in "$@"; do
        if grep -Fq "$needle" <<< "$text"; then
            return 0
        fi
    done
    return 1
}

echo "1) Kontrollin keskkonna valikut ja ligipääsu dokumentatsioonis..."
if ! has_any "$DOC_CONTENT" "raspberry pi" "ubuntu server" "wsl2" "wsl 2"; then
    echo "FAIL: Dokumentatsioonis puudub valitud Linuxi keskkond."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "ssh" "konsool" "console"; then
    echo "FAIL: Dokumentatsioonis puudub info, kuidas keskkonda sisse logitakse (konsool/SSH)."
    exit 1
fi
echo "OK"

echo "2) Kontrollin MariaDB paigaldust..."
if ! command -v mariadb >/dev/null 2>&1; then
    echo "FAIL: mariadb käsk puudub."
    exit 1
fi
MARIADB_VERSION="$(mariadb --version 2>/dev/null || true)"
if [[ -z "$MARIADB_VERSION" ]]; then
    echo "FAIL: MariaDB versiooni ei õnnestunud lugeda."
    exit 1
fi
echo "MariaDB: $MARIADB_VERSION"

SERVICE_ENABLED="unknown"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled mariadb >/dev/null 2>&1; then
        SERVICE_ENABLED="enabled"
    elif systemctl is-enabled mysql >/dev/null 2>&1; then
        SERVICE_ENABLED="enabled"
    else
        SERVICE_ENABLED="not-enabled"
    fi
fi
echo "Autostart: $SERVICE_ENABLED"
if ! has_any "$DOC_CONTENT" "mariadb --version" "versioon" "version"; then
    echo "FAIL: Dokumentatsioonis puudub MariaDB versiooni info."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "automaatselt" "is-enabled" "enabled" "autostart"; then
    echo "FAIL: Dokumentatsioonis puudub info teenuse automaatse käivitumise kohta."
    exit 1
fi
echo "OK"

run_sql() {
    local sql="$1"
    if sudo -n true >/dev/null 2>&1; then
        sudo mariadb -N -B -u root -e "$sql" 2>/dev/null && return 0
    fi
    mariadb -N -B -u root -e "$sql" 2>/dev/null
}

echo "3) Kontrollin esmast turvaseadistust..."
anon_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='';" || echo "ERR")"
testdb_count="$(run_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='test';" || echo "ERR")"
root_remote_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='root' AND host NOT IN ('localhost','127.0.0.1','::1');" || echo "ERR")"
root_plugin="$(run_sql "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost' LIMIT 1;" || echo "ERR")"

if [[ "$anon_count" == "ERR" || "$testdb_count" == "ERR" || "$root_remote_count" == "ERR" || "$root_plugin" == "ERR" ]]; then
    echo "FAIL: SQL kontroll ebaõnnestus (kasuta sudo mariadb -u root)."
    exit 1
fi

echo "Root plugin: $root_plugin"
echo "Anonymous users: $anon_count"
echo "Test DB count: $testdb_count"
echo "Root remote logins: $root_remote_count"

if [[ "$anon_count" -ne 0 ]]; then
    echo "FAIL: Anonüümsed kasutajad on eemaldamata."
    exit 1
fi
if [[ "$testdb_count" -ne 0 ]]; then
    echo "FAIL: test andmebaas on eemaldamata."
    exit 1
fi
if [[ "$root_remote_count" -ne 0 ]]; then
    echo "FAIL: root remote login pole keelatud."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "unix_socket" "auth_socket"; then
    echo "FAIL: Dokumentatsioonis puudub märge unix_socket autentimise valiku kohta."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "anon" "anonü" "anonymous"; then
    echo "FAIL: Dokumentatsioonis puudub märge anonüümsete kasutajate eemaldamise kohta."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "testandmebaas" "test database" "schema_name='test'" "drop database test"; then
    echo "FAIL: Dokumentatsioonis puudub märge testandmebaasi eemaldamise kohta."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "root remote" "remote login" "root login"; then
    echo "FAIL: Dokumentatsioonis puudub märge root remote login'i keelamise kohta."
    exit 1
fi
echo "OK"

echo "4) Kontrollin võrguturbe konfiguratsiooni..."
CNF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [[ ! -f "$CNF_FILE" ]]; then
    echo "FAIL: Konfiguratsioonifaili ei leitud: $CNF_FILE"
    exit 1
fi
if ! grep -Eq '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*127\.0\.0\.1' "$CNF_FILE"; then
    echo "FAIL: bind-address = 127.0.0.1 puudub."
    exit 1
fi
if ! grep -Eq '^[[:space:]]*local-infile[[:space:]]*=[[:space:]]*0' "$CNF_FILE"; then
    echo "FAIL: local-infile = 0 puudub."
    exit 1
fi
if ! grep -Eq '^[[:space:]]*skip-name-resolve([[:space:]]*=[[:space:]]*1)?' "$CNF_FILE"; then
    echo "FAIL: skip-name-resolve puudub."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "bind-address" "local-infile" "skip-name-resolve"; then
    echo "FAIL: Dokumentatsioonis puuduvad tehtud config muudatused."
    exit 1
fi
echo "OK"

echo "5) Kontrollin teenuse seisu ja pordi nähtavust..."
service_ok=0
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        service_ok=1
    fi
fi
if [[ "$service_ok" -ne 1 ]]; then
    echo "FAIL: MariaDB teenus ei ole aktiivne."
    exit 1
fi

PORT_LINE="$(ss -tlnp 2>/dev/null | grep -E '(:3306\\b|mariadbd|mysqld)' | head -n1 || true)"
if [[ -n "$PORT_LINE" ]]; then
    echo "Port check: 3306/open or process visible"
else
    echo "Port check: 3306 not visible (possible with skip-networking=1)"
fi

BIND_ADDR="$(run_sql "SHOW VARIABLES LIKE 'bind_address';" | awk '{print $2}' | head -n1 || true)"
if [[ -z "$BIND_ADDR" ]]; then
    echo "FAIL: bind_address muutujat ei õnnestunud lugeda."
    exit 1
fi
echo "bind_address: $BIND_ADDR"

if ! has_any "$DOC_CONTENT" "3306" "port" "ss -tlnp"; then
    echo "FAIL: Dokumentatsioonis puudub pordi 3306 tulemus."
    exit 1
fi
if ! has_any "$DOC_CONTENT" "ekraanitõmmis" "screenshot" "screen"; then
    echo "FAIL: Dokumentatsioonis puudub märge andmebaasi ekraanitõmmise kohta."
    exit 1
fi
echo "OK"

echo "Task 1 passed."
send_result 1
