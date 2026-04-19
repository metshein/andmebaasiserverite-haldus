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

    if [[ -f "$bash_history_file" ]] && tr -d '`' < "$bash_history_file" | grep -Eiq "$pattern"; then
        return 0
    fi

    if [[ -f "$mysql_history_file" ]] && tr -d '`' < "$mysql_history_file" | grep -Eiq "$pattern"; then
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

target_schema="lab_perf"
target_table="users"
archive_table="users_archive"

db_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$target_schema';" || echo "0")"
if [[ "$db_exists" -eq 0 ]]; then
    fail "Andmebaasi $target_schema ei leitud."
    echo "Kohustuslikke puudusi: $mandatory_fails"
    echo -e "${RED}Task 05: MITTE ARVESTATUD${NC}"
    exit 1
fi

table_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$target_schema' AND TABLE_NAME='$target_table';" || echo "0")"
if [[ "$table_exists" -eq 0 ]]; then
    fail "Tabelit $target_schema.$target_table ei leitud."
    echo "Kohustuslikke puudusi: $mandatory_fails"
    echo -e "${RED}Task 05: MITTE ARVESTATUD${NC}"
    exit 1
fi

ok "Kasutan andmebaasi $target_schema ja tabelit $target_table."

info "1-2) Kontrollin CHECK TABLE käskude kasutust..."

mapfile -t db_tables < <(run_sql "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$target_schema' ORDER BY TABLE_NAME;" || true)

if [[ "${#db_tables[@]}" -eq 0 ]]; then
    fail "Andmebaasis $target_schema ei leitud tabeleid."
else
    check_cmd_hits=0
    missing_tables=()

    for t in "${db_tables[@]}"; do
        if history_has "CHECK[[:space:]]+TABLE[[:space:]]+($target_schema\\.)?$t([[:space:];]|$)"; then
            check_cmd_hits=$((check_cmd_hits + 1))
        else
            missing_tables+=("$t")
        fi
    done

    if [[ "$check_cmd_hits" -eq "${#db_tables[@]}" ]]; then
        ok "CHECK TABLE käsku on kasutatud iga tabeli jaoks eraldi ($check_cmd_hits/${#db_tables[@]})."
    else
        fail "CHECK TABLE käsku ei leitud kõigi tabelite jaoks eraldi ($check_cmd_hits/${#db_tables[@]})."
        warn "Puuduvad CHECK TABLE tõendid tabelitele: ${missing_tables[*]}"
    fi
fi

info "3) Kontrollin arhiveerimist (esimesed 50 000 kirjet)..."

archive_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$target_schema' AND TABLE_NAME='$archive_table';" || echo "0")"
if [[ "$archive_exists" -eq 0 ]]; then
    fail "Arhiivitabelit $target_schema.$archive_table ei leitud."
else
    ok "Arhiivitabel $target_schema.$archive_table on olemas."
fi

if [[ "$archive_exists" -gt 0 ]]; then
    users_def="$(run_sql "SELECT GROUP_CONCAT(CONCAT(COLUMN_NAME,':',COLUMN_TYPE,':',IS_NULLABLE,':',IFNULL(COLUMN_DEFAULT,'NULL'),':',EXTRA) ORDER BY ORDINAL_POSITION SEPARATOR '|') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$target_schema' AND TABLE_NAME='$target_table';" || true)"
    archive_def="$(run_sql "SELECT GROUP_CONCAT(CONCAT(COLUMN_NAME,':',COLUMN_TYPE,':',IS_NULLABLE,':',IFNULL(COLUMN_DEFAULT,'NULL'),':',EXTRA) ORDER BY ORDINAL_POSITION SEPARATOR '|') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$target_schema' AND TABLE_NAME='$archive_table';" || true)"

    if [[ -z "$users_def" || -z "$archive_def" ]]; then
        fail "Tabelite struktuuride võrdlus ebaõnnestus."
    elif [[ "$users_def" == "$archive_def" ]]; then
        ok "$archive_table struktuur vastab tabelile $target_table."
    else
        fail "$archive_table struktuur ei vasta tabelile $target_table."
    fi
fi

archive_count="0"
if [[ "$archive_exists" -gt 0 ]]; then
    archive_count="$(run_sql "SELECT COUNT(*) FROM $target_schema.$archive_table;" || echo "0")"
    if [[ "$archive_count" -lt 50000 ]]; then
        fail "Arhiivitabelis on vähem kui 50 000 kirjet (hetkel $archive_count)."
    else
        ok "Arhiivitabelis on $archive_count kirjet."
        if [[ "$archive_count" -gt 50000 ]]; then
            warn "Arhiivitabelis on üle 50 000 kirje (võimalik, et arhiveerimist tehti mitu korda)."
        fi
    fi

    first_50k_archived="$(run_sql "SELECT COUNT(*) FROM (SELECT id FROM (SELECT id FROM $target_schema.$archive_table UNION ALL SELECT id FROM $target_schema.$target_table) x ORDER BY id LIMIT 50000) f JOIN $target_schema.$archive_table a USING(id);" || echo "0")"
    if [[ "$first_50k_archived" -eq 50000 ]]; then
        ok "Esimesed 50 000 id-d paiknevad arhiivitabelis."
    else
        fail "Esimeste 50 000 id-de arhiveerimise kontroll ebaõnnestus (leitud $first_50k_archived/50000)."
    fi
fi

info "4) Kontrollin ANALYZE TABLE users kasutust..."

analyze_history_found=0
if history_has 'ANALYZE[[:space:]]+TABLE[[:space:]]+`?users`?'; then
    analyze_history_found=1
fi

analyze_recent="$(run_sql "SELECT COUNT(*) FROM mysql.innodb_table_stats WHERE database_name='$target_schema' AND table_name='$target_table' AND last_update >= NOW() - INTERVAL 1 DAY;" || echo "ERR")"

if [[ "$analyze_history_found" -eq 1 ]]; then
    ok "Käsuajaloos leidub ANALYZE TABLE users kasutust."
elif [[ "$analyze_recent" != "ERR" && "$analyze_recent" -gt 0 ]]; then
    ok "InnoDB statistika järgi on users tabelit hiljuti uuendatud (ANALYZE tõend olemas)."
else
    fail "ANALYZE TABLE users tõendit ei leitud (ajalugu ega hiljutine statistika uuendus)."
fi

info "5) Tulemuste kontroll..."

if [[ "$archive_exists" -gt 0 ]]; then
    users_count="$(run_sql "SELECT COUNT(*) FROM $target_schema.$target_table;" || echo "0")"
    combined_count=$((users_count + archive_count))
    if [[ "$combined_count" -gt "$users_count" ]]; then
        ok "Aktiivne tabel $target_table sisaldab nüüd vähem kirjeid kui $target_table + $archive_table kokku."
    else
        fail "Aktiivne tabel ei paista pärast arhiveerimist vähenenud."
    fi

    status_users="$(run_sql "CHECK TABLE $target_schema.$target_table;" || true)"
    status_archive="$(run_sql "CHECK TABLE $target_schema.$archive_table;" || true)"

    if echo "$status_users" | awk -F'\t' 'tolower($3)=="error" {exit 0} END {exit 1}'; then
        fail "Lõppkontrollis on $target_table tabel vigane."
    else
        ok "Lõppkontrollis on $target_table tabel korras."
    fi

    if echo "$status_archive" | awk -F'\t' 'tolower($3)=="error" {exit 0} END {exit 1}'; then
        fail "Lõppkontrollis on $archive_table tabel vigane."
    else
        ok "Lõppkontrollis on $archive_table tabel korras."
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
