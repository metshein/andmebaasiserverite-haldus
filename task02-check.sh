#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mandatory_fails=0

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

run_sql_raw() {
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
        sudo "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

audit_grep() {
    local pattern="$1"
    local file="$2"
    if sudo -n true >/dev/null 2>&1; then
        sudo grep -Ei "$pattern" "$file" >/dev/null 2>&1
    else
        grep -Ei "$pattern" "$file" >/dev/null 2>&1
    fi
}

require_token_in_csv() {
    local token="$1"
    local csv_upper="$2"
    echo "$csv_upper" | tr -d ' ' | grep -Eq "(^|,)$token(,|$)"
}

grants_has_default_role() {
    local grants_text="$1"
    local role_name="$2"
    echo "$grants_text" | grep -Fqi "SET DEFAULT ROLE \\`$role_name\\`" || \
    echo "$grants_text" | grep -Fqi "SET DEFAULT ROLE $role_name"
}

if ! command -v mariadb >/dev/null 2>&1; then
    echo -e "${RED}VIGA:${NC} MariaDB kaasku ei leitud (mariadb puudub PATH-is)."
    exit 1
fi

if ! run_sql "SELECT 1;" >/dev/null; then
    echo -e "${RED}VIGA:${NC} MariaDB uhendus ebaonnestus."
    echo "Vihje: kasuta DB_USER/DB_PASS (ja soovi korral DB_HOST/DB_PORT) voi luba sudo mariadb."
    exit 1
fi

info "1) Kontrollin andmebaasi ettevalmistust..."

db_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='lab_users';" || echo "ERR")"
if [[ "$db_exists" == "ERR" || "$db_exists" -eq 0 ]]; then
    fail "Andmebaasi lab_users ei leitud."
else
    ok "Andmebaas lab_users on olemas."
fi

table_exists="$(run_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='lab_users' AND TABLE_NAME='actions';" || echo "ERR")"
if [[ "$table_exists" == "ERR" || "$table_exists" -eq 0 ]]; then
    fail "Tabelit lab_users.actions ei leitud."
else
    ok "Tabel lab_users.actions on olemas."
fi

if [[ "$table_exists" != "ERR" && "$table_exists" -gt 0 ]]; then
    id_col_ok="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_users' AND TABLE_NAME='actions' AND COLUMN_NAME='id' AND COLUMN_KEY='PRI' AND EXTRA LIKE '%auto_increment%';" || echo "0")"
    desc_col_ok="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_users' AND TABLE_NAME='actions' AND COLUMN_NAME='description' AND DATA_TYPE='varchar' AND IS_NULLABLE='NO';" || echo "0")"
    created_col_ok="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='lab_users' AND TABLE_NAME='actions' AND COLUMN_NAME='created_at' AND DATA_TYPE='datetime' AND IS_NULLABLE='NO' AND (UPPER(COLUMN_DEFAULT) LIKE 'CURRENT_TIMESTAMP%' OR UPPER(COLUMN_DEFAULT) LIKE 'NOW%');" || echo "0")"

    if [[ "$id_col_ok" -eq 0 || "$desc_col_ok" -eq 0 || "$created_col_ok" -eq 0 ]]; then
        fail "Tabeli actions veerud/vaikevaartused ei vasta nouetele."
    else
        ok "Tabeli actions struktuur vastab nouetele."
    fi

    row_count="$(run_sql "SELECT COUNT(*) FROM lab_users.actions;" || echo "0")"
    if [[ "$row_count" -lt 2 ]]; then
        fail "Tabelis actions peab olema vahemalt 2 kirjet (hetkel $row_count)."
    else
        ok "Tabelis actions on vahemalt 2 kirjet."
    fi

    missing_created_at="$(run_sql "SELECT COUNT(*) FROM lab_users.actions WHERE created_at IS NULL;" || echo "1")"
    if [[ "$missing_created_at" -gt 0 ]]; then
        fail "Mone kirje created_at on NULL."
    else
        ok "Kirjete created_at on automaatselt taisidetud."
    fi
fi

info "2) Kontrollin paroolipoliitikat ja nourga parooli tagasilukkamist..."

simple_plugin_status="$(run_sql "SELECT PLUGIN_STATUS FROM information_schema.PLUGINS WHERE UPPER(PLUGIN_NAME)='SIMPLE_PASSWORD_CHECK' LIMIT 1;" || true)"
if [[ "$simple_plugin_status" != "ACTIVE" ]]; then
    fail "Plugin simple_password_check peab olema ACTIVE."
else
    ok "simple_password_check on ACTIVE."
fi

cracklib_plugin_status="$(run_sql "SELECT PLUGIN_STATUS FROM information_schema.PLUGINS WHERE UPPER(PLUGIN_NAME)='CRACKLIB_PASSWORD_CHECK' LIMIT 1;" || true)"
if [[ "$cracklib_plugin_status" != "ACTIVE" ]]; then
    fail "Plugin cracklib_password_check peab olema ACTIVE."
else
    ok "cracklib_password_check on ACTIVE."
fi

sp_min_len="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_minimal_length';" | awk '{print $2}' | head -n1 || true)"
sp_digits="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_digits';" | awk '{print $2}' | head -n1 || true)"
sp_letters_legacy="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_letters';" | awk '{print $2}' | head -n1 || true)"
sp_letters_same="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_letters_same_case';" | awk '{print $2}' | head -n1 || true)"
sp_letters_other="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_letters_other_case';" | awk '{print $2}' | head -n1 || true)"
sp_symbols="$(run_sql "SHOW VARIABLES LIKE 'simple_password_check_other_characters';" | awk '{print $2}' | head -n1 || true)"

letters_total=0
if [[ -n "$sp_letters_legacy" ]]; then
    letters_total="$sp_letters_legacy"
elif [[ -n "$sp_letters_same" || -n "$sp_letters_other" ]]; then
    letters_total=0
fi
if [[ -n "$sp_letters_same" ]]; then
    letters_total=$((letters_total + sp_letters_same))
fi
if [[ -n "$sp_letters_other" ]]; then
    letters_total=$((letters_total + sp_letters_other))
fi

if [[ -z "$sp_min_len" || "$sp_min_len" -lt 10 ]]; then
    fail "Parooli miinimumpikkus peab olema vahemalt 10."
else
    ok "Parooli miinimumpikkus on vahemalt 10."
fi

if [[ -z "$sp_digits" || "$sp_digits" -lt 1 ]]; then
    fail "Paroolireegel peab noudma vahemalt 1 numbri."
else
    ok "Paroolireegel nouab vahemalt 1 numbri."
fi

if [[ "$letters_total" -lt 1 ]]; then
    fail "Paroolireegel peab noudma vahemalt 1 tahe."
else
    ok "Paroolireegel nouab vahemalt 1 tahte."
fi

if [[ -z "$sp_symbols" || "$sp_symbols" -lt 1 ]]; then
    fail "Paroolireegel peab noudma vahemalt 1 symbolit."
else
    ok "Paroolireegel nouab vahemalt 1 symbolit."
fi

set +e
weak_output="$(run_sql_raw "DROP USER IF EXISTS 'weak_task02_check'@'localhost'; CREATE USER 'weak_task02_check'@'localhost' IDENTIFIED BY 'abc';" 2>&1)"
weak_rc=$?
set -e
run_sql "DROP USER IF EXISTS 'weak_task02_check'@'localhost';" >/dev/null || true

if [[ "$weak_rc" -eq 0 ]]; then
    fail "Nork parool ei saanud tagasi lykatud (CREATE USER onnestus)."
else
    ok "Nork parool lykati tagasi."
fi

info "3) Kontrollin kasutajad, oigused ja rollid..."

admin_count="$(run_sql "SELECT COUNT(*) FROM mysql.db WHERE Db='lab_users' AND Select_priv='Y' AND Insert_priv='Y' AND Update_priv='Y' AND Delete_priv='Y' AND Create_priv='Y' AND Drop_priv='Y' AND User NOT IN ('root','mysql','mariadb.sys');" || echo "0")"
if [[ "$admin_count" -lt 1 ]]; then
    fail "Ei leidnud admin kasutajat, kellel oleks lab_users andmebaasile taisoigused."
else
    ok "Leidsin vahemalt 1 admin kasutaja taisoigustega lab_users andmebaasile."
fi

has_is_role="$(run_sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='mysql' AND TABLE_NAME='user' AND COLUMN_NAME='is_role';" || echo "0")"

if [[ "$has_is_role" -gt 0 ]]; then
    ro_users_count="$(run_sql "SELECT COUNT(DISTINCT principal) FROM (SELECT t.GRANTEE AS principal FROM information_schema.TABLE_PRIVILEGES t JOIN mysql.user u ON t.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE t.TABLE_SCHEMA='lab_users' AND t.TABLE_NAME='actions' AND u.is_role<>'Y' AND u.User NOT IN ('root','mysql','mariadb.sys') GROUP BY t.GRANTEE HAVING MAX(t.PRIVILEGE_TYPE='SELECT')=1 AND MAX(t.PRIVILEGE_TYPE='INSERT')=0 AND MAX(t.PRIVILEGE_TYPE='UPDATE')=0 AND MAX(t.PRIVILEGE_TYPE='DELETE')=0 UNION SELECT CONCAT(\"'\",rm.User,\"'@'\",rm.Host,\"'\") AS principal FROM mysql.roles_mapping rm JOIN mysql.user uu ON uu.User=rm.User AND uu.Host=rm.Host JOIN (SELECT u.User AS role_name FROM (SELECT t.GRANTEE, MAX(t.PRIVILEGE_TYPE='SELECT') sel, MAX(t.PRIVILEGE_TYPE='INSERT') ins, MAX(t.PRIVILEGE_TYPE='UPDATE') upd, MAX(t.PRIVILEGE_TYPE='DELETE') del FROM information_schema.TABLE_PRIVILEGES t JOIN mysql.user u ON t.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE t.TABLE_SCHEMA='lab_users' AND t.TABLE_NAME='actions' AND u.is_role='Y' GROUP BY t.GRANTEE) r JOIN mysql.user u ON r.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE r.sel=1 AND r.ins=0 AND r.upd=0 AND r.del=0) rr ON rr.role_name = rm.Role WHERE uu.is_role<>'Y' AND uu.User NOT IN ('root','mysql','mariadb.sys')) all_principals;" || echo "0")"
else
    ro_users_count="$(run_sql "SELECT COUNT(*) FROM (SELECT GRANTEE, MAX(PRIVILEGE_TYPE='SELECT') sel, MAX(PRIVILEGE_TYPE='INSERT') ins, MAX(PRIVILEGE_TYPE='UPDATE') upd, MAX(PRIVILEGE_TYPE='DELETE') del FROM information_schema.TABLE_PRIVILEGES WHERE TABLE_SCHEMA='lab_users' AND TABLE_NAME='actions' GROUP BY GRANTEE) x WHERE sel=1 AND ins=0 AND upd=0 AND del=0;" || echo "0")"
fi

if [[ "$ro_users_count" -lt 2 ]]; then
    fail "Ei leidnud vahemalt 2 ainult lugemisoigusega tavakasutajat tabelile lab_users.actions."
else
    ok "Leidsin vahemalt 2 ainult lugemisoigusega tavakasutajat."
fi

if [[ "$has_is_role" -gt 0 ]]; then
    reader_role_name="$(run_sql "SELECT u.User FROM (SELECT t.GRANTEE, MAX(t.PRIVILEGE_TYPE='SELECT') sel, MAX(t.PRIVILEGE_TYPE='INSERT') ins, MAX(t.PRIVILEGE_TYPE='UPDATE') upd, MAX(t.PRIVILEGE_TYPE='DELETE') del FROM information_schema.TABLE_PRIVILEGES t JOIN mysql.user u ON t.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE t.TABLE_SCHEMA='lab_users' AND t.TABLE_NAME='actions' AND u.is_role='Y' GROUP BY t.GRANTEE) r JOIN mysql.user u ON r.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE r.sel=1 AND r.ins=0 AND r.upd=0 AND r.del=0 LIMIT 1;" || true)"
    poster_role_name="$(run_sql "SELECT u.User FROM (SELECT t.GRANTEE, MAX(t.PRIVILEGE_TYPE='SELECT') sel, MAX(t.PRIVILEGE_TYPE='INSERT') ins, MAX(t.PRIVILEGE_TYPE='UPDATE') upd, MAX(t.PRIVILEGE_TYPE='DELETE') del FROM information_schema.TABLE_PRIVILEGES t JOIN mysql.user u ON t.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE t.TABLE_SCHEMA='lab_users' AND t.TABLE_NAME='actions' AND u.is_role='Y' GROUP BY t.GRANTEE) r JOIN mysql.user u ON r.GRANTEE = CONCAT(\"'\",u.User,\"'@'\",u.Host,\"'\") WHERE r.sel=1 AND r.ins=1 AND r.upd=1 AND r.del=1 LIMIT 1;" || true)"

    if [[ -z "$reader_role_name" ]]; then
        fail "Ei leidnud lugeja-tyypi rolli (ainult SELECT tabelile lab_users.actions)."
    else
        ok "Leidsin lugeja-tyypi rolli: $reader_role_name"
    fi

    if [[ -z "$poster_role_name" ]]; then
        fail "Ei leidnud postitaja-tyypi rolli (SELECT+INSERT+UPDATE+DELETE tabelile lab_users.actions)."
    else
        ok "Leidsin postitaja-tyypi rolli: $poster_role_name"
    fi

    if [[ -n "$reader_role_name" ]]; then
        reader_user="$(run_sql "SELECT rm.User FROM mysql.roles_mapping rm JOIN mysql.user u ON u.User=rm.User AND u.Host=rm.Host WHERE rm.Role='$reader_role_name' AND u.is_role<>'Y' AND u.User NOT IN ('root','mysql','mariadb.sys') LIMIT 1;" || true)"
        reader_host="$(run_sql "SELECT rm.Host FROM mysql.roles_mapping rm JOIN mysql.user u ON u.User=rm.User AND u.Host=rm.Host WHERE rm.Role='$reader_role_name' AND u.is_role<>'Y' AND u.User NOT IN ('root','mysql','mariadb.sys') LIMIT 1;" || true)"
        if [[ -z "$reader_user" || -z "$reader_host" ]]; then
            fail "Lugeja roll ei ole seotud yhegi kasutajaga."
        else
            ok "Lugeja roll on seotud kasutajaga $reader_user@$reader_host"
            role_count_user="$(run_sql "SELECT COUNT(*) FROM mysql.roles_mapping WHERE User='$reader_user' AND Host='$reader_host';" || echo "0")"
            if [[ "$role_count_user" -ne 1 ]]; then
                fail "Kasutajal $reader_user@$reader_host peab olema tapselt 1 roll (hetkel $role_count_user)."
            else
                ok "Kasutajal $reader_user@$reader_host on tapselt 1 roll."
            fi

            default_grants="$(run_sql "SHOW GRANTS FOR '$reader_user'@'$reader_host';" || true)"
            if grants_has_default_role "$default_grants" "$reader_role_name"; then
                ok "Lugeja roll on vaikimisi aktiivne kasutajal $reader_user@$reader_host."
            else
                fail "Lugeja roll ei paista olevat vaikimisi aktiivne kasutajal $reader_user@$reader_host."
            fi
        fi
    fi

    if [[ -n "$poster_role_name" ]]; then
        poster_user="$(run_sql "SELECT rm.User FROM mysql.roles_mapping rm JOIN mysql.user u ON u.User=rm.User AND u.Host=rm.Host WHERE rm.Role='$poster_role_name' AND u.is_role<>'Y' AND u.User NOT IN ('root','mysql','mariadb.sys') LIMIT 1;" || true)"
        poster_host="$(run_sql "SELECT rm.Host FROM mysql.roles_mapping rm JOIN mysql.user u ON u.User=rm.User AND u.Host=rm.Host WHERE rm.Role='$poster_role_name' AND u.is_role<>'Y' AND u.User NOT IN ('root','mysql','mariadb.sys') LIMIT 1;" || true)"
        if [[ -z "$poster_user" || -z "$poster_host" ]]; then
            fail "Postitaja roll ei ole seotud yhegi kasutajaga."
        else
            ok "Postitaja roll on seotud kasutajaga $poster_user@$poster_host"
            role_count_user="$(run_sql "SELECT COUNT(*) FROM mysql.roles_mapping WHERE User='$poster_user' AND Host='$poster_host';" || echo "0")"
            if [[ "$role_count_user" -ne 1 ]]; then
                fail "Kasutajal $poster_user@$poster_host peab olema tapselt 1 roll (hetkel $role_count_user)."
            else
                ok "Kasutajal $poster_user@$poster_host on tapselt 1 roll."
            fi

            default_grants="$(run_sql "SHOW GRANTS FOR '$poster_user'@'$poster_host';" || true)"
            if grants_has_default_role "$default_grants" "$poster_role_name"; then
                ok "Postitaja roll on vaikimisi aktiivne kasutajal $poster_user@$poster_host."
            else
                fail "Postitaja roll ei paista olevat vaikimisi aktiivne kasutajal $poster_user@$poster_host."
            fi
        fi
    fi
else
    warn "MariaDB versioonis puudub mysql.user.is_role; rollide detailkontroll jaeti vahele."
fi

info "4) Kontrollin auditiplugina seadistust ja auditisyndmusi..."

audit_plugin_status="$(run_sql "SELECT PLUGIN_STATUS FROM information_schema.PLUGINS WHERE UPPER(PLUGIN_NAME)='SERVER_AUDIT' LIMIT 1;" || true)"
if [[ "$audit_plugin_status" != "ACTIVE" ]]; then
    fail "Plugin server_audit peab olema paigaldatud ja ACTIVE."
else
    ok "server_audit plugin on ACTIVE."
fi

audit_logging="$(run_sql "SHOW VARIABLES LIKE 'server_audit_logging';" | awk '{print toupper($2)}' | head -n1 || true)"
if [[ "$audit_logging" != "ON" ]]; then
    fail "server_audit_logging peab olema ON."
else
    ok "server_audit_logging on ON."
fi

audit_events="$(run_sql "SHOW VARIABLES LIKE 'server_audit_events';" | awk '{print toupper($2)}' | head -n1 || true)"
if [[ -z "$audit_events" ]]; then
    fail "server_audit_events vaartus on tyhi."
elif require_token_in_csv "ALL" "$audit_events"; then
    ok "server_audit_events on ALL (sisaldab koiki nouutud syndmuseid)."
else
    missing_evt=0
    for evt in CONNECT QUERY QUERY_DDL QUERY_DML QUERY_DCL; do
        if ! require_token_in_csv "$evt" "$audit_events"; then
            fail "server_audit_events ei sisalda nouetud syndmust: $evt"
            missing_evt=1
        fi
    done
    if [[ "$missing_evt" -eq 0 ]]; then
        ok "server_audit_events sisaldab koiki nouutud syndmuseid."
    fi
fi

audit_file_path="$(run_sql "SHOW VARIABLES LIKE 'server_audit_file_path';" | awk '{print $2}' | head -n1 || true)"
if [[ -z "$audit_file_path" ]]; then
    fail "server_audit_file_path on maaramata."
else
    if [[ "$audit_file_path" != /* ]]; then
        datadir="$(run_sql "SHOW VARIABLES LIKE 'datadir';" | awk '{print $2}' | head -n1 || true)"
        audit_file_path="${datadir%/}/$audit_file_path"
    fi

    if sudo -n true >/dev/null 2>&1; then
        sudo test -r "$audit_file_path" || fail "Auditlogi faili ei saa lugeda: $audit_file_path"
    else
        test -r "$audit_file_path" || fail "Auditlogi faili ei saa lugeda: $audit_file_path"
    fi

    marker="task02_audit_$(date +%s)"
    dcl_user="audit_${marker}"
    dcl_pass="Aa1!Aa1!Aa1!"

    run_sql "CREATE TABLE IF NOT EXISTS lab_users.audit_probe_${marker} (id INT);" >/dev/null || true
    run_sql "INSERT INTO lab_users.actions (description) VALUES ('$marker');" >/dev/null || true
    run_sql "CREATE USER '$dcl_user'@'localhost' IDENTIFIED BY '$dcl_pass';" >/dev/null || true
    run_sql "GRANT SELECT ON lab_users.actions TO '$dcl_user'@'localhost';" >/dev/null || true
    run_sql "REVOKE SELECT ON lab_users.actions FROM '$dcl_user'@'localhost';" >/dev/null || true
    run_sql "DROP USER '$dcl_user'@'localhost';" >/dev/null || true
    run_sql "DROP TABLE IF EXISTS lab_users.audit_probe_${marker};" >/dev/null || true

    if audit_grep "CONNECT" "$audit_file_path"; then
        ok "Auditlogis leidub CONNECT syndmusi."
    else
        fail "Auditlogist ei leidnud CONNECT syndmust."
    fi

    if audit_grep "QUERY_DDL|,DDL,|CREATE TABLE|DROP TABLE" "$audit_file_path"; then
        ok "Auditlogis leidub DDL syndmusi."
    else
        fail "Auditlogist ei leidnud DDL syndmust."
    fi

    if audit_grep "$marker|QUERY_DML|,WRITE,|INSERT INTO" "$audit_file_path"; then
        ok "Auditlogis leidub DML syndmusi."
    else
        fail "Auditlogist ei leidnud DML syndmust."
    fi

    if audit_grep "QUERY_DCL|GRANT |REVOKE " "$audit_file_path"; then
        ok "Auditlogis leidub DCL syndmusi."
    else
        fail "Auditlogist ei leidnud DCL syndmust."
    fi

    if audit_grep "QUERY" "$audit_file_path"; then
        ok "Auditlogis leidub QUERY syndmusi."
    else
        fail "Auditlogist ei leidnud QUERY syndmust."
    fi
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 02 edukalt labitud."
    send_result 2
else
    echo -e "${RED}Task 02: MITTE ARVESTATUD${NC}"
    exit 1
fi
