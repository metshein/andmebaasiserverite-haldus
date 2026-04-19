#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mandatory_fails=0
bash_history_file="${HISTFILE:-$HOME/.bash_history}"
mysql_history_file="$HOME/.mysql_history"

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

    if [[ -f "$bash_history_file" ]] && grep -Eiq "$pattern" "$bash_history_file"; then
        return 0
    fi

    if [[ -f "$mysql_history_file" ]] && grep -Eiq "$pattern" "$mysql_history_file"; then
        return 0
    fi

    return 1
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

accounts_schema="$(run_sql "SELECT TABLE_SCHEMA FROM information_schema.TABLES WHERE TABLE_NAME='accounts' AND TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys') ORDER BY TABLE_SCHEMA LIMIT 1;" || true)"

if [[ -z "$accounts_schema" ]]; then
    fail "Tabelit accounts ei leitud ühestki kasutaja andmebaasist."
    echo "Kohustuslikke puudusi: $mandatory_fails"
    echo -e "${RED}Task 05: MITTE ARVESTATUD${NC}"
    exit 1
fi

ok "Leidsin accounts tabeli andmebaasist: $accounts_schema"

info "1) Kontrollin tabelite seisukorda (CHECK TABLE)..."

mapfile -t db_tables < <(run_sql "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$accounts_schema' ORDER BY TABLE_NAME;" || true)

if [[ "${#db_tables[@]}" -eq 0 ]]; then
    fail "Andmebaasis $accounts_schema ei leitud tabeleid."
else
    check_error_tables=0
    check_warning_tables=0

    for t in "${db_tables[@]}"; do
        check_output="$(run_sql "CHECK TABLE $accounts_schema.$t;" || true)"
        if [[ -z "$check_output" ]]; then
            fail "CHECK TABLE ei andnud väljundit tabelile $accounts_schema.$t"
            continue
        fi

        if echo "$check_output" | awk -F'\t' 'tolower($3)=="error" {exit 0} END {exit 1}'; then
            fail "CHECK TABLE näitas viga tabelis $accounts_schema.$t"
            check_error_tables=$((check_error_tables + 1))
        elif echo "$check_output" | awk -F'\t' 'tolower($3)=="warning" {exit 0} END {exit 1}'; then
            warn "CHECK TABLE näitas hoiatust tabelis $accounts_schema.$t"
            check_warning_tables=$((check_warning_tables + 1))
        else
            ok "Tabel $accounts_schema.$t on korras."
        fi
    done

    info "CHECK TABLE kokkuvõte: vead=$check_error_tables, hoiatused=$check_warning_tables"
fi

info "2) Hinnangu kontroll (tehniline tõend)..."
if history_has 'CHECK[[:space:]]+TABLE'; then
    ok "Käsuajaloos leidub CHECK TABLE kasutust."
else
    warn "Käsuajaloost ei leitud CHECK TABLE käsku (võis olla tehtud teises sessioonis)."
fi

info "3) Analüüsin accounts mahtu ja kasutust..."

accounts_count="$(run_sql "SELECT COUNT(*) FROM $accounts_schema.accounts;" || echo "0")"
accounts_size_bytes="$(run_sql "SELECT IFNULL(DATA_LENGTH+INDEX_LENGTH,0) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$accounts_schema' AND TABLE_NAME='accounts';" || echo "0")"

if [[ "$accounts_count" -le 0 ]]; then
    fail "Tabelis $accounts_schema.accounts pole kirjeid."
else
    ok "Tabelis $accounts_schema.accounts on $accounts_count kirjet."
fi

if [[ "$accounts_size_bytes" -le 0 ]]; then
    fail "Tabeli accounts suurust ei õnnestunud korrektselt lugeda."
else
    ok "Tabeli accounts ligikaudne suurus: $accounts_size_bytes baiti."
fi

info "4) Kontrollin arhiveerimist (esimesed 50 000 kirjet)..."

archive_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$accounts_schema' AND TABLE_NAME='accounts_archive';" || echo "0")"
if [[ "$archive_exists" -eq 0 ]]; then
    fail "Arhiivitabelit $accounts_schema.accounts_archive ei leitud."
else
    ok "Arhiivitabel $accounts_schema.accounts_archive on olemas."
fi

if [[ "$archive_exists" -gt 0 ]]; then
    accounts_def="$(run_sql "SELECT GROUP_CONCAT(CONCAT(COLUMN_NAME,':',COLUMN_TYPE,':',IS_NULLABLE,':',IFNULL(COLUMN_DEFAULT,'NULL'),':',EXTRA) ORDER BY ORDINAL_POSITION SEPARATOR '|') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$accounts_schema' AND TABLE_NAME='accounts';" || true)"
    archive_def="$(run_sql "SELECT GROUP_CONCAT(CONCAT(COLUMN_NAME,':',COLUMN_TYPE,':',IS_NULLABLE,':',IFNULL(COLUMN_DEFAULT,'NULL'),':',EXTRA) ORDER BY ORDINAL_POSITION SEPARATOR '|') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$accounts_schema' AND TABLE_NAME='accounts_archive';" || true)"

    if [[ -z "$accounts_def" || -z "$archive_def" ]]; then
        fail "Tabelite struktuuride võrdlus ebaõnnestus."
    elif [[ "$accounts_def" == "$archive_def" ]]; then
        ok "accounts_archive struktuur vastab tabelile accounts."
    else
        fail "accounts_archive struktuur ei vasta tabelile accounts."
    fi
fi

archive_count="0"
if [[ "$archive_exists" -gt 0 ]]; then
    archive_count="$(run_sql "SELECT COUNT(*) FROM $accounts_schema.accounts_archive;" || echo "0")"
    if [[ "$archive_count" -lt 50000 ]]; then
        fail "Arhiivitabelis on vähem kui 50 000 kirjet (hetkel $archive_count)."
    else
        ok "Arhiivitabelis on $archive_count kirjet."
        if [[ "$archive_count" -gt 50000 ]]; then
            warn "Arhiivitabelis on üle 50 000 kirje (võimalik, et arhiveerimist tehti mitu korda)."
        fi
    fi

    first_50k_archived="$(run_sql "SELECT COUNT(*) FROM (SELECT id FROM (SELECT id FROM $accounts_schema.accounts_archive UNION ALL SELECT id FROM $accounts_schema.accounts) x ORDER BY id LIMIT 50000) f JOIN $accounts_schema.accounts_archive a USING(id);" || echo "0")"
    if [[ "$first_50k_archived" -eq 50000 ]]; then
        ok "Esimesed 50 000 id-d paiknevad arhiivitabelis."
    else
        fail "Esimeste 50 000 id-de arhiveerimise kontroll ebaõnnestus (leitud $first_50k_archived/50000)."
    fi
fi

info "5) Kontrollin ANALYZE TABLE accounts kasutust..."

analyze_history_found=0
if history_has 'ANALYZE[[:space:]]+TABLE[[:space:]]+`?accounts`?'; then
    analyze_history_found=1
fi

analyze_recent="$(run_sql "SELECT COUNT(*) FROM mysql.innodb_table_stats WHERE database_name='$accounts_schema' AND table_name='accounts' AND last_update >= NOW() - INTERVAL 1 DAY;" || echo "ERR")"

if [[ "$analyze_history_found" -eq 1 ]]; then
    ok "Käsuajaloos leidub ANALYZE TABLE accounts kasutust."
elif [[ "$analyze_recent" != "ERR" && "$analyze_recent" -gt 0 ]]; then
    ok "InnoDB statistika järgi on accounts tabelit hiljuti uuendatud (ANALYZE tõend olemas)."
else
    fail "ANALYZE TABLE accounts tõendit ei leitud (ajalugu ega hiljutine statistika uuendus)."
fi

info "6) Tulemuste kontroll..."

if [[ "$archive_exists" -gt 0 ]]; then
    combined_count=$((accounts_count + archive_count))
    if [[ "$combined_count" -gt "$accounts_count" ]]; then
        ok "Aktiivne tabel accounts sisaldab nüüd vähem kirjeid kui accounts + accounts_archive kokku."
    else
        fail "Aktiivne tabel ei paista pärast arhiveerimist vähenenud."
    fi

    status_accounts="$(run_sql "CHECK TABLE $accounts_schema.accounts;" || true)"
    status_archive="$(run_sql "CHECK TABLE $accounts_schema.accounts_archive;" || true)"

    if echo "$status_accounts" | awk -F'\t' 'tolower($3)=="error" {exit 0} END {exit 1}'; then
        fail "Lõppkontrollis on accounts tabel vigane."
    else
        ok "Lõppkontrollis on accounts tabel korras."
    fi

    if echo "$status_archive" | awk -F'\t' 'tolower($3)=="error" {exit 0} END {exit 1}'; then
        fail "Lõppkontrollis on accounts_archive tabel vigane."
    else
        ok "Lõppkontrollis on accounts_archive tabel korras."
    fi
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 05 edukalt läbitud."
    send_result 5
else
    echo -e "${RED}Task 05: MITTE ARVESTATUD${NC}"
    exit 1
fi
