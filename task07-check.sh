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

info "1) Kontrollin veebiserveri olemasolu..."

web_server_found=0
web_server_note=""

if command -v apache2 >/dev/null 2>&1; then
    web_server_found=1
    web_server_note="Apache (apache2) on olemas."
elif command -v httpd >/dev/null 2>&1; then
    web_server_found=1
    web_server_note="Apache (httpd) on olemas."
elif command -v nginx >/dev/null 2>&1; then
    web_server_found=1
    web_server_note="Nginx on olemas."
fi

if [[ "$web_server_found" -eq 1 ]]; then
    ok "$web_server_note"
else
    fail "Veebiserverit ei leitud (apache2/httpd/nginx puudub)."
fi

info "2) Kontrollin PHP ja MySQL laiendusi..."

if command -v php >/dev/null 2>&1; then
    php_version="$(php -v 2>/dev/null | head -n1 || true)"
    if [[ -n "$php_version" ]]; then
        ok "PHP on olemas: $php_version"
    else
        ok "PHP on olemas."
    fi
else
    fail "PHP ei ole leitud (puudub php käsk)."
fi

php_mysql_ext_found=0
php_mysql_ext_note=""
if command -v php >/dev/null 2>&1; then
    if php -m 2>/dev/null | grep -Eiq '^(mysqli|pdo_mysql)$'; then
        php_mysql_ext_found=1
        php_mysql_ext_note="PHP MySQL laiendus on olemas (mysqli või pdo_mysql)."
    elif php -m 2>/dev/null | grep -Eiq '^mysqlnd$'; then
        php_mysql_ext_note="Leidsin mysqlnd, kuid Admineri jaoks tuleks kontrollida ka mysqli või pdo_mysql olemasolu."
    fi
fi

if [[ "$php_mysql_ext_found" -eq 1 ]]; then
    ok "$php_mysql_ext_note"
else
    fail "PHP MySQL laiendust ei leitud (vajalik on mysqli või pdo_mysql)."
    if [[ -n "$php_mysql_ext_note" ]]; then
        warn "$php_mysql_ext_note"
    fi
fi

info "3) Kontrollin Admineri paigaldust..."

adminer_found=0
adminer_path=""

for p in \
    /usr/share/adminer/adminer.php \
    /usr/share/webapps/adminer/adminer.php \
    /var/lib/adminer/adminer.php \
    /var/www/html/adminer.php \
    /var/www/html/adminer/adminer.php \
    /usr/share/phpmyadmin/adminer.php; do
    if [[ -f "$p" ]]; then
        adminer_found=1
        adminer_path="$p"
        break
    fi
done

if [[ "$adminer_found" -eq 0 ]] && command -v dpkg >/dev/null 2>&1; then
    if dpkg -l 2>/dev/null | awk '$2=="adminer" && $1 ~ /^ii$/ {found=1} END {exit !found}'; then
        adminer_found=1
    fi
fi

if [[ "$adminer_found" -eq 1 ]]; then
    if [[ -n "$adminer_path" ]]; then
        ok "Adminer on olemas: $adminer_path"
    else
        ok "Adminer on paigaldatud (paketitõend)."
    fi
else
    fail "Adminerit ei leitud (ei kaustast ega paketihaldurist)."
fi

info "4) Kontrollin Admineri ligipääsetavuse seoseid..."

adminer_alias_found=0
for c in \
    /etc/apache2/conf-enabled/adminer.conf \
    /etc/apache2/conf-available/adminer.conf \
    /etc/nginx/conf.d/adminer.conf \
    /etc/nginx/sites-enabled/adminer.conf; do
    if [[ -f "$c" ]]; then
        adminer_alias_found=1
        break
    fi
done

if [[ "$adminer_alias_found" -eq 1 ]]; then
    ok "Admineri veebiserveri konfiguratsioon on olemas."
else
    warn "Admineri veebiserveri konfiguratsioonifaili ei leitud (võib olla käsitsi seadistatud või Adminer on otse veebijuures)."
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 07 edukalt läbitud."
    send_result 7
else
    echo -e "${RED}Task 07: MITTE ARVESTATUD${NC}"
    exit 1
fi
