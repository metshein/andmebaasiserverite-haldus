#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mandatory_fails=0
history_file="${HISTFILE:-$HOME/.bash_history}"

info() {
    echo -e "${BLUE}$1${NC}"
}

ok() {
    echo -e "${GREEN}OK:${NC} $1"
}

warn() {
    echo -e "${YELLOW}MARKUS:${NC} $1"
}

fail() {
    echo -e "${RED}VIGA:${NC} $1"
    mandatory_fails=$((mandatory_fails + 1))
}

run_sql() {
    local sql="$1"
    local -a cmd=(mariadb -N -B)

    if [[ -n "${DB_HOST:-}" ]]; then
        cmd+=(-h "$DB_HOST")
    fi
    if [[ -n "${DB_PORT:-}" ]]; then
        cmd+=(-P "$DB_PORT")
    fi
    if [[ -n "${DB_USER:-}" ]]; then
        cmd+=(-u "$DB_USER")
    fi
    if [[ -n "${DB_PASS:-}" ]]; then
        cmd+=(-p"$DB_PASS")
    fi
    cmd+=(-e "$sql")

    if [[ "${DB_USE_SUDO:-auto}" == "always" ]] || { [[ "${DB_USE_SUDO:-auto}" == "auto" ]] && [[ -z "${DB_USER:-}" ]] && sudo -n true >/dev/null 2>&1; }; then
        sudo "${cmd[@]}" 2>/dev/null
    else
        "${cmd[@]}" 2>/dev/null
    fi
}

history_has() {
    local pattern="$1"
    if [[ ! -f "$history_file" ]]; then
        return 1
    fi
    grep -Eiq "$pattern" "$history_file"
}

if ! command -v mariadb >/dev/null 2>&1; then
    echo -e "${RED}VIGA:${NC} MariaDB käsku ei leitud (mariadb puudub PATH-is)."
    exit 1
fi

if ! run_sql "SELECT 1;" >/dev/null; then
    echo -e "${RED}VIGA:${NC} MariaDB ühendus ebaõnnestus."
    echo "Vihje: kasuta DB_USER/DB_PASS (ja soovi korral DB_HOST/DB_PORT) või luba sudo mariadb."
    exit 1
fi

info "1) Kontrollin andmebaasi ettevalmistust..."

db_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='lab_perf';" || echo "0")"
if [[ "$db_exists" -eq 0 ]]; then
    fail "Andmebaasi lab_perf ei leitud."
else
    ok "Andmebaas lab_perf on olemas."
fi

table_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users';" || echo "0")"
if [[ "$table_exists" -eq 0 ]]; then
    fail "Tabelit lab_perf.users ei leitud."
else
    ok "Tabel lab_perf.users on olemas."
fi

if [[ "$table_exists" -gt 0 ]]; then
    id_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND COLUMN_NAME='id' AND COLUMN_KEY='PRI' AND EXTRA LIKE '%auto_increment%';" || echo "0")"
    email_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND COLUMN_NAME='email' AND DATA_TYPE='varchar';" || echo "0")"
    city_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND COLUMN_NAME='city' AND DATA_TYPE='varchar';" || echo "0")"
    balance_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND COLUMN_NAME='balance' AND DATA_TYPE='decimal';" || echo "0")"
    created_at_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND COLUMN_NAME='created_at' AND DATA_TYPE='datetime';" || echo "0")"

    if [[ "$id_col" -eq 0 || "$email_col" -eq 0 || "$city_col" -eq 0 || "$balance_col" -eq 0 || "$created_at_col" -eq 0 ]]; then
        fail "Tabeli users struktuur ei vasta nõuetele (id, email, city, balance, created_at)."
    else
        ok "Tabeli users struktuur vastab nõuetele."
    fi
fi

info "2) Kontrollin testandmeid..."

if [[ "$table_exists" -gt 0 ]]; then
    row_count="$(run_sql "SELECT COUNT(*) FROM lab_perf.users;" || echo "0")"
    if [[ "$row_count" -lt 100000 ]]; then
        fail "Tabelis users on vähem kui 100000 kirjet (hetkel $row_count)."
    else
        ok "Tabelis users on $row_count kirjet."
    fi

    lihula_count="$(run_sql "SELECT COUNT(*) FROM lab_perf.users WHERE city='Lihula';" || echo "0")"
    if [[ "$lihula_count" -eq 0 ]]; then
        fail "Linna 'Lihula' kirjeid ei leitud (UPDATE kontroll ebaõnnestus)."
    else
        ok "Linna 'Lihula' kirjeid leiti: $lihula_count."
    fi
fi

info "3) Kontrollin city indeksi mõju..."

idx_city_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND INDEX_NAME='idx_city';" || echo "0")"
if [[ "$idx_city_exists" -eq 0 ]]; then
    fail "Indeksit idx_city ei leitud."
else
    ok "Indeks idx_city on olemas."
fi

if [[ "$table_exists" -gt 0 && "$idx_city_exists" -gt 0 ]]; then
    explain_city="$(run_sql "EXPLAIN FORMAT=JSON SELECT * FROM lab_perf.users WHERE city='Lihula';" || true)"
    if [[ -z "$explain_city" ]]; then
        fail "EXPLAIN FORMAT=JSON city päringule ebaõnnestus."
    else
        ok "EXPLAIN FORMAT=JSON city päringule töötab."
    fi
fi

info "4) Kontrollin ORDER BY ja balance indeksit..."

idx_balance_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='lab_perf' AND TABLE_NAME='users' AND INDEX_NAME='idx_balance';" || echo "0")"
if [[ "$idx_balance_exists" -eq 0 ]]; then
    fail "Indeksit idx_balance ei leitud."
else
    ok "Indeks idx_balance on olemas."
fi

if [[ "$table_exists" -gt 0 ]]; then
    explain_sort="$(run_sql "EXPLAIN FORMAT=JSON SELECT * FROM lab_perf.users WHERE city='Lihula' ORDER BY balance;" || true)"
    if [[ -z "$explain_sort" ]]; then
        fail "EXPLAIN FORMAT=JSON ORDER BY päringule ebaõnnestus."
    else
        ok "EXPLAIN FORMAT=JSON ORDER BY päringule töötab."
    fi
fi

info "5) Kontrollin slow query logi..."

slow_log_enabled="$(run_sql "SHOW VARIABLES LIKE 'slow_query_log';" | awk '{print toupper($2)}' | head -n1 || true)"
if [[ "$slow_log_enabled" == "ON" ]]; then
    ok "slow_query_log on ON."
else
    info "slow_query_log on hetkel OFF."
fi

long_query_time_val="$(run_sql "SHOW VARIABLES LIKE 'long_query_time';" | awk '{print $2}' | head -n1 || true)"
if [[ -n "$long_query_time_val" ]]; then
    ok "long_query_time väärtus: $long_query_time_val"
else
    info "long_query_time väärtust ei õnnestunud lugeda."
fi

slow_log_file="$(run_sql "SHOW VARIABLES LIKE 'slow_query_log_file';" | awk '{print $2}' | head -n1 || true)"
if [[ -z "$slow_log_file" ]]; then
    fail "slow_query_log_file asukohta ei õnnestunud lugeda."
elif [[ -f "$slow_log_file" ]]; then
    if grep -Eiq 'SELECT[[:space:]]+\*.*users|SELECT[[:space:]]+SLEEP\(1\)' "$slow_log_file"; then
        ok "Slow logis leidub vähemalt üks asjakohane päring."
    else
        info "Slow logis ei leitud kasutajate päringut ega SLEEP(1) kirjet."
    fi
else
    info "Slow logi faili ei leitud teest: $slow_log_file"
fi

info "6) Kontrollin konfiguratsiooni seose osa..."

innodb_bp="$(run_sql "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{print $2}' | head -n1 || true)"
max_conn="$(run_sql "SHOW VARIABLES LIKE 'max_connections';" | awk '{print $2}' | head -n1 || true)"

if [[ -n "$innodb_bp" && "$innodb_bp" -gt 0 ]]; then
    ok "innodb_buffer_pool_size loetud: $innodb_bp"
else
    fail "innodb_buffer_pool_size väärtust ei õnnestunud korrektselt lugeda."
fi

if [[ -n "$max_conn" && "$max_conn" -gt 0 ]]; then
    ok "max_connections loetud: $max_conn"
else
    fail "max_connections väärtust ei õnnestunud korrektselt lugeda."
fi

info "7) Paindlik käsuajaloo kontroll (alternatiivtõendid)..."

if [[ -f "$history_file" ]]; then
    history_hits=0

    history_has 'EXPLAIN[[:space:]]+FORMAT=JSON[[:space:]]+SELECT[[:space:]]+\*.*users.*city' && history_hits=$((history_hits + 1))
    history_has 'CREATE[[:space:]]+INDEX[[:space:]]+idx_city[[:space:]]+ON[[:space:]]+users' && history_hits=$((history_hits + 1))
    history_has 'CREATE[[:space:]]+INDEX[[:space:]]+idx_balance[[:space:]]+ON[[:space:]]+users' && history_hits=$((history_hits + 1))
    history_has 'SET[[:space:]]+GLOBAL[[:space:]]+slow_query_log[[:space:]]*=[[:space:]]*ON' && history_hits=$((history_hits + 1))
    history_has 'SET[[:space:]]+GLOBAL[[:space:]]+long_query_time[[:space:]]*=[[:space:]]*0\.5' && history_hits=$((history_hits + 1))
    history_has 'SELECT[[:space:]]+SLEEP\(1\)' && history_hits=$((history_hits + 1))
    history_has 'SHOW[[:space:]]+VARIABLES[[:space:]]+LIKE[[:space:]]+.innodb_buffer_pool_size.' && history_hits=$((history_hits + 1))
    history_has 'SHOW[[:space:]]+VARIABLES[[:space:]]+LIKE[[:space:]]+.max_connections.' && history_hits=$((history_hits + 1))

    if [[ "$history_hits" -ge 1 ]]; then
        ok "Käsuajaloos leiti töövoo samme ($history_hits/8)."
    else
        info "Käsuajaloos ei leitud töövoo samme (0/8). Kui tegid tööd teises sessioonis, käivita enne kontrolli history -a."
    fi
else
    info "Bash ajaloo faili ei leitud; alternatiivkontroll jäeti vahele."
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 04 edukalt läbitud."
    send_result 4
else
    echo -e "${RED}Task 04: MITTE ARVESTATUD${NC}"
    exit 1
fi
