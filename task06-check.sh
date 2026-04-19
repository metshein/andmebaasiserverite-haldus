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

info "1) Kontrollin Apache olemasolu..."

apache_found=0
apache_version=""
apache_detect_note=""

if command -v apache2 >/dev/null 2>&1; then
    apache_version="$(apache2 -v 2>/dev/null | head -n1 || true)"
    if echo "$apache_version" | grep -Eiq 'apache'; then
        apache_found=1
    else
        apache_detect_note="Leidsin käsu apache2, kuid versioonis pole Apache tunnust."
    fi
elif command -v httpd >/dev/null 2>&1; then
    apache_version="$(httpd -v 2>/dev/null | head -n1 || true)"
    if echo "$apache_version" | grep -Eiq 'apache'; then
        apache_found=1
    else
        apache_detect_note="Leidsin käsu httpd, kuid see ei paista olevat Apache HTTP Server."
    fi
fi

if [[ "$apache_found" -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
    if systemctl status apache2 >/dev/null 2>&1 || systemctl status httpd >/dev/null 2>&1; then
        apache_found=1
        apache_detect_note="Apache teenuse unit on olemas (tuvastus systemctl kaudu)."
    fi
fi

if [[ "$apache_found" -eq 1 ]]; then
    if [[ -n "$apache_version" ]]; then
        ok "Apache on olemas: $apache_version"
    elif [[ -n "$apache_detect_note" ]]; then
        ok "Apache on olemas: $apache_detect_note"
    else
        ok "Apache on olemas."
    fi
else
    fail "Apache ei ole leitud (ei tuvastatud Apache versiooni ega teenuse unitit)."
    if [[ -n "$apache_detect_note" ]]; then
        warn "$apache_detect_note"
    fi
fi

apache_service_state="unknown"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet apache2; then
        apache_service_state="active (apache2)"
    elif systemctl is-active --quiet httpd; then
        apache_service_state="active (httpd)"
    elif systemctl status apache2 >/dev/null 2>&1 || systemctl status httpd >/dev/null 2>&1; then
        apache_service_state="installed-but-not-active"
    fi
fi

if [[ "$apache_service_state" == active* ]]; then
    ok "Apache teenus töötab: $apache_service_state"
elif [[ "$apache_service_state" == "installed-but-not-active" ]]; then
    warn "Apache on paigaldatud, kuid teenus ei tööta."
else
    warn "Apache teenuse olekut ei õnnestunud kinnitada systemctl abil."
fi

info "2) Kontrollin PHP olemasolu..."

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

info "3) Kontrollin phpMyAdmin olemasolu..."

phpmyadmin_found=0
phpmyadmin_path=""

for p in \
    /usr/share/phpmyadmin \
    /usr/share/phpMyAdmin \
    /var/www/html/phpmyadmin \
    /var/www/html/phpMyAdmin \
    /var/www/phpmyadmin \
    /var/www/phpMyAdmin \
    /etc/phpmyadmin \
    /usr/share/webapps/phpMyAdmin; do
    if [[ -d "$p" ]]; then
        phpmyadmin_found=1
        phpmyadmin_path="$p"
        break
    fi
done

if [[ "$phpmyadmin_found" -eq 0 ]] && command -v dpkg >/dev/null 2>&1; then
    if dpkg -l 2>/dev/null | awk '$2=="phpmyadmin" && $1 ~ /^ii$/ {found=1} END {exit !found}'; then
        phpmyadmin_found=1
    fi
fi

if [[ "$phpmyadmin_found" -eq 1 ]]; then
    if [[ -n "$phpmyadmin_path" ]]; then
        ok "phpMyAdmin on olemas: $phpmyadmin_path"
    else
        ok "phpMyAdmin on paigaldatud (paketitõend)."
    fi
else
    fail "phpMyAdmini ei leitud (ei kaustast ega paketihaldurist)."
fi

echo
echo "Kohustuslikke puudusi: $mandatory_fails"

if [[ "$mandatory_fails" -eq 0 ]]; then
    ok "Task 06 edukalt läbitud."
    send_result 6
else
    echo -e "${RED}Task 06: MITTE ARVESTATUD${NC}"
    exit 1
fi
