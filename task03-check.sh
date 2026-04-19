#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mandatory_fails=0
manual_email="${MANUAL_EMAIL:-eesnimi.perenimi@example.com}"

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

if ! command -v mariadb >/dev/null 2>&1; then
    echo -e "${RED}VIGA:${NC} MariaDB käsku ei leitud (mariadb puudub PATH-is)."
    exit 1
fi

if ! run_sql "SELECT 1;" >/dev/null; then
    echo -e "${RED}VIGA:${NC} MariaDB ühendus ebaõnnestus."
    echo "Vihje: kasuta DB_USER/DB_PASS (ja soovi korral DB_HOST/DB_PORT) või luba sudo mariadb."
    exit 1
fi

info "1) Kontrollin andmebaasi ja tabeli loomist..."

db_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='backup_lab';" || echo "0")"
if [[ "$db_exists" -eq 0 ]]; then
    fail "Andmebaasi backup_lab ei leitud."
else
    ok "Andmebaas backup_lab on olemas."
fi

table_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers';" || echo "0")"
if [[ "$table_exists" -eq 0 ]]; then
    fail "Tabelit backup_lab.customers ei leitud."
else
    ok "Tabel backup_lab.customers on olemas."
fi

if [[ "$table_exists" -gt 0 ]]; then
    id_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='id' AND COLUMN_KEY='PRI' AND EXTRA LIKE '%auto_increment%';" || echo "0")"
    first_name_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='first_name' AND DATA_TYPE='varchar' AND IS_NULLABLE='NO';" || echo "0")"
    last_name_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='last_name' AND DATA_TYPE='varchar' AND IS_NULLABLE='NO';" || echo "0")"
    email_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='email' AND DATA_TYPE='varchar' AND IS_NULLABLE='NO';" || echo "0")"
    city_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='city';" || echo "0")"
    created_at_col="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers' AND COLUMN_NAME='created_at' AND DATA_TYPE='datetime' AND IS_NULLABLE='NO';" || echo "0")"

    if [[ "$id_col" -eq 0 || "$first_name_col" -eq 0 || "$last_name_col" -eq 0 || "$email_col" -eq 0 || "$city_col" -eq 0 || "$created_at_col" -eq 0 ]]; then
        fail "Tabeli customers veerud ei vasta nõuetele (id, first_name, last_name, email, city, created_at)."
    else
        ok "Tabeli customers struktuur on korrektne."
    fi
fi

info "2) Kontrollin andmete importi..."

if [[ "$table_exists" -gt 0 ]]; then
    row_count="$(run_sql "SELECT COUNT(*) FROM backup_lab.customers;" || echo "0")"
    if [[ "$row_count" -lt 1000 ]]; then
        fail "Tabelis customers on alla 1000 kirje (hetkel $row_count). Kas importisite Mockaroo andmed?"
    else
        ok "Tabelis customers on $row_count kirjet."
    fi

    if [[ "$row_count" -lt 1001 ]]; then
        fail "Tabelis customers peab olema vähemalt 1001 kirjet (1000 imporditud + vähemalt 1 käsitsi lisatud kirje)."
    else
        ok "Tabelis customers on vähemalt 1001 kirjet."
    fi

    manual_row_count="$(run_sql "SELECT COUNT(*) FROM backup_lab.customers WHERE email='${manual_email}';" || echo "0")"
    if [[ "$manual_row_count" -gt 0 ]]; then
        ok "Käsitsi lisatud kirje e-postiga ${manual_email} on olemas."
    else
        warn "Käsitsi lisatud kirjet e-postiga ${manual_email} ei leitud. Kui kasutasid teist e-posti, käivita kontroll uuesti: MANUAL_EMAIL='sinu@epost.ee' ./task03-check.sh"
    fi

    null_created_at="$(run_sql "SELECT COUNT(*) FROM backup_lab.customers WHERE created_at IS NULL;" || echo "0")"
    if [[ "$null_created_at" -gt 0 ]]; then
        fail "Mõne kirje created_at on NULL."
    else
        ok "Kõigi kirjete created_at väärtused on täidetud."
    fi
fi

info "3) Kontrollin loogilist varukoopiat..."

logical_backup_file="/tmp/backup_lab.sql"
if [[ ! -f "$logical_backup_file" ]]; then
    fail "Loogilise varukoopia faili $logical_backup_file ei leitud. Kas tegite 'mariadb-dump backup_lab > /tmp/backup_lab.sql'?"
else
    file_size=$(stat -f%z "$logical_backup_file" 2>/dev/null || stat -c%s "$logical_backup_file" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 100 ]]; then
        fail "Loogilise varukoopia fail on liiga väike (${file_size} baiti)."
    else
        ok "Loogilise varukoopia fail $logical_backup_file eksisteerib (${file_size} baiti)."
    fi

    if grep -q "CREATE TABLE.*customers" "$logical_backup_file"; then
        ok "Loogilises varukoopias leidub CREATE TABLE lause."
    else
        fail "Loogilises varukoopias ei leidunud CREATE TABLE lauset."
    fi

    if grep -q "DROP TABLE.*customers" "$logical_backup_file"; then
        ok "Loogilises varukoopias leidub DROP TABLE lause."
    else
        warn "Loogilises varukoopias ei leidunud DROP TABLE lauset."
    fi

    if grep -q "INSERT INTO.*customers" "$logical_backup_file"; then
        ok "Loogilises varukoopias leidub INSERT INTO lause."
    else
        fail "Loogilises varukoopias ei leidunud INSERT INTO lauset."
    fi
fi

info "4) Kontrollin füüsilist varukoopiat..."

physical_backup_dir="/tmp/physical_backup"
if [[ ! -d "$physical_backup_dir" ]]; then
    fail "Füüsilise varukoopia kataloogi $physical_backup_dir ei leitud. Kas tegite 'mariadb-backup --backup --target-dir=/tmp/physical_backup'?"
else
    ok "Füüsilise varukoopia kataloog $physical_backup_dir eksisteerib."

    if [[ ! -f "$physical_backup_dir/backup-my.cnf" ]]; then
        fail "Füüsilises varukoopias puudub backup-my.cnf fail."
    else
        ok "Füüsilises varukoopias leidub backup-my.cnf fail."
    fi

    if [[ -f "$physical_backup_dir/mariadb_backup_info" ]]; then
        ok "Füüsilises varukoopias leidub mariadb_backup_info fail."
    elif [[ -f "$physical_backup_dir/xtrabackup_info" ]]; then
        ok "Füüsilises varukoopias leidub varukoopia infofail."
    else
        fail "Füüsilises varukoopias puudub varukoopia infofail. Ülesandes on nõutud mariadb-backup kasutamine."
    fi

    if [[ -f "$physical_backup_dir/xtrabackup_checkpoints" ]] || [[ -f "$physical_backup_dir/mariadb_backup_checkpoints" ]]; then
        ok "Füüsilises varukoopias leidub kontrollpunktide fail."
    else
        fail "Füüsilises varukoopias puudub kontrollpunktide fail. Veendu, et varunduskäsk lõppes teatega 'completed OK!' ja et --target-dir osutab õigele kataloogile."
    fi

    if [[ ! -d "$physical_backup_dir/backup_lab" ]]; then
        fail "Füüsilises varukoopias puudub backup_lab andmebaasi kataloog."
    else
        ok "Füüsilises varukoopias leidub backup_lab kataloog."
    fi
fi

info "5) Kontrollin varunduskasutajat (füüsilisele varundusele)..."

backup_user_exists="$(run_sql "SELECT COUNT(*) FROM mysql.user WHERE User='mariadb_backup';" || echo "0")"
if [[ "$backup_user_exists" -gt 0 ]]; then
    ok "Varunduskasutaja 'mariadb_backup' on olemas."
    
    backup_user_privs="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='mysql' AND COLUMN_NAME='Backup_priv';" || echo "0")"
    if [[ "$backup_user_privs" -gt 0 ]]; then
        backup_priv="$(run_sql "SELECT Backup_priv FROM mysql.user WHERE User='mariadb_backup' LIMIT 1;" || true)"
        if [[ "$backup_priv" == "Y" ]]; then
            ok "Varunduskasutajal on BACKUP_ADMIN privileeg."
        else
            warn "Varunduskasutajal ei ole BACKUP_ADMIN privileegi (Backup_priv != Y)."
        fi
    fi
else
    warn "Varunduskasutajat 'mariadb_backup' ei leitud."
fi

cnf_file="/root/.my.cnf"
if [[ ! -f "$cnf_file" ]]; then
    warn "Autentimisinfo faili $cnf_file ei leitud. Füüsiline varundus või selle tegemine ei ole toiminud."
else
    ok "Autentimisinfo fail $cnf_file eksisteerib."
fi

info "6) Kokkuvõte varundamisest..."

if [[ -f "$logical_backup_file" ]] && [[ -d "$physical_backup_dir" ]]; then
    ok "Nii loogiline kui ka füüsiline varukoopia on tehtud."
elif [[ -f "$logical_backup_file" ]]; then
    warn "Ainult loogiline varukoopia on tehtud. Füüsiline varukoopia puudub."
elif [[ -d "$physical_backup_dir" ]]; then
    warn "Ainult füüsiline varukoopia on tehtud. Loogiline varukoopia puudub."
else
    fail "Kumbki varukoopia ei ole tehtud."
fi

info "7) Kontrollin taastamise lõpptulemust..."

restored_db_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='backup_lab';" || echo "0")"
if [[ "$restored_db_exists" -eq 0 ]]; then
    fail "Taastamise järel andmebaasi backup_lab ei leitud."
else
    ok "Taastamise järel on andmebaas backup_lab olemas."
fi

restored_table_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='backup_lab' AND TABLE_NAME='customers';" || echo "0")"
if [[ "$restored_table_exists" -eq 0 ]]; then
    fail "Taastamise järel tabelit backup_lab.customers ei leitud."
else
    ok "Taastamise järel on tabel backup_lab.customers olemas."
fi

if [[ "$restored_table_exists" -gt 0 ]]; then
    restored_row_count="$(run_sql "SELECT COUNT(*) FROM backup_lab.customers;" || echo "0")"
    if [[ "$restored_row_count" -lt 1001 ]]; then
        fail "Taastamise järel on tabelis customers liiga vähe kirjeid (hetkel $restored_row_count, oodatud vähemalt 1001)."
    else
        ok "Taastamise järel on tabelis customers vähemalt 1001 kirjet."
    fi

    restored_manual_row_count="$(run_sql "SELECT COUNT(*) FROM backup_lab.customers WHERE email='${manual_email}';" || echo "0")"
    if [[ "$restored_manual_row_count" -gt 0 ]]; then
        ok "Taastamise järel leidub käsitsi lisatud kirje e-postiga ${manual_email}."
    else
        warn "Taastamise järel ei leitud kirjet e-postiga ${manual_email}. Kui kasutasid teist e-posti, määra MANUAL_EMAIL ja käivita kontroll uuesti."
    fi
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 03 edukalt läbitud."
    send_result 3
else
    echo -e "${RED}Task 03: MITTE ARVESTATUD${NC}"
    exit 1
fi
