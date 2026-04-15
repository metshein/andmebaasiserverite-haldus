#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}$1${NC}"
}

ok() {
    echo -e "${GREEN}OK:${NC} $1"
}

warn() {
    echo -e "${YELLOW}MÄRKUS:${NC} $1"
}

fail() {
    echo -e "${RED}VIGA:${NC} $1"
    exit 1
}

run_sql() {
    local sql="$1"
    if sudo -n true >/dev/null 2>&1; then
        sudo mariadb -N -B -u root -e "$sql" 2>/dev/null && return 0
    fi
    mariadb -N -B -u root -e "$sql" 2>/dev/null
}

info "1) Kontrollin, kas MariaDB on paigaldatud ja versioon loetav..."
if ! command -v mariadb >/dev/null 2>&1; then
    fail "MariaDB käsku ei leitud (mariadb puudub PATH-is)."
fi

MARIADB_VERSION="$(mariadb --version 2>/dev/null || true)"
if [[ -z "$MARIADB_VERSION" ]]; then
    fail "MariaDB versiooni ei õnnestunud lugeda."
fi
ok "MariaDB on olemas: $MARIADB_VERSION"

SERVICE_ENABLED="unknown"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled mariadb >/dev/null 2>&1 || systemctl is-enabled mysql >/dev/null 2>&1; then
        SERVICE_ENABLED="enabled"
    else
        SERVICE_ENABLED="not-enabled"
    fi
fi
ok "Teenuse automaatkäivituse staatus: $SERVICE_ENABLED"

info "2) Kontrollin esmase turvaseadistuse tulemusi..."
anon_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='';" || echo "ERR")"
testdb_count="$(run_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='test';" || echo "ERR")"
root_remote_count="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE user='root' AND host NOT IN ('localhost','127.0.0.1','::1');" || echo "ERR")"
root_plugin="$(run_sql "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost' LIMIT 1;" || echo "ERR")"

if [[ "$anon_count" == "ERR" || "$testdb_count" == "ERR" || "$root_remote_count" == "ERR" || "$root_plugin" == "ERR" ]]; then
    fail "SQL kontroll ebaõnnestus (proovi sudo mariadb -u root)."
fi

if [[ "$anon_count" -ne 0 ]]; then
    fail "Anonüümsed kasutajad on eemaldamata (count=$anon_count)."
fi
if [[ "$testdb_count" -ne 0 ]]; then
    fail "Test andmebaas on eemaldamata (count=$testdb_count)."
fi
if [[ "$root_remote_count" -ne 0 ]]; then
    fail "Root remote login ei ole piiratud (count=$root_remote_count)."
fi

ok "Turvaseadistus korras (root plugin: $root_plugin, anon=0, test=0, remote_root=0)"

info "3) Kontrollin võrgu turvakonfiguratsiooni failist..."
CNF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [[ ! -f "$CNF_FILE" ]]; then
    fail "Konfiguratsioonifaili ei leitud: $CNF_FILE"
fi

if ! grep -Eq '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*127\.0\.0\.1' "$CNF_FILE"; then
    fail "Rida puudub või vale: bind-address = 127.0.0.1"
fi
if ! grep -Eq '^[[:space:]]*local-infile[[:space:]]*=[[:space:]]*0' "$CNF_FILE"; then
    fail "Rida puudub või vale: local-infile = 0"
fi
if ! grep -Eq '^[[:space:]]*skip-name-resolve([[:space:]]*=[[:space:]]*1)?' "$CNF_FILE"; then
    fail "Rida puudub: skip-name-resolve"
fi
ok "Konfiguratsioonifaili turvaread on paigas."

info "4) Kontrollin teenuse tööd ja sidumisseadeid..."
service_ok=0
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        service_ok=1
    fi
fi

if [[ "$service_ok" -ne 1 ]]; then
    fail "MariaDB teenus ei ole aktiivne."
fi
ok "MariaDB teenus on aktiivne."

PORT_LINE="$(ss -tlnp 2>/dev/null | grep -E '(:3306\\b|mariadbd|mysqld)' | head -n1 || true)"
if [[ -n "$PORT_LINE" ]]; then
    ok "Pordi kontroll: 3306/protsess on nähtav."
else
    warn "Port 3306 ei paista (see võib olla korrektne, kui skip-networking=1)."
fi

BIND_ADDR="$(run_sql "SHOW VARIABLES LIKE 'bind_address';" | awk '{print $2}' | head -n1 || true)"
if [[ -z "$BIND_ADDR" ]]; then
    fail "MariaDB bind_address väärtust ei õnnestunud lugeda."
fi
ok "bind_address väärtus: $BIND_ADDR"

ok "Task 1 edukalt läbitud."
send_result 1
