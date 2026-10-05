#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

print_success() { echo -e "  ${GREEN}✔${RESET} $1"; }
print_info()    { echo -e "  ${CYAN}→${RESET} $1"; }

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run uninstaller with sudo.${RESET}"
    exit 1
fi

read -rp "Uninstall PortLabel and all configured routes? (y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Cancelled."; exit 0; }

systemctl stop portlabel-web > /dev/null 2>&1
systemctl disable portlabel-web > /dev/null 2>&1
rm -f /etc/systemd/system/portlabel-web.service
systemctl daemon-reload
print_success "Removed portlabel-web service"

rm -f /usr/local/bin/portlabel
rm -rf /usr/local/lib/portlabel
print_success "Removed PortLabel binary and libraries"

if grep -q "# portlabel-start" /etc/hosts 2>/dev/null; then
    tmp=$(mktemp)
    awk '
        /# portlabel-start/ { skip=1 }
        !skip { print }
        /# portlabel-end/ { skip=0 }
    ' /etc/hosts > "$tmp"
    cp "$tmp" /etc/hosts
    rm -f "$tmp"
    print_success "Cleaned /etc/hosts"
fi

CADDYFILE="/etc/caddy/Caddyfile"
CADDY_CONF="/etc/caddy/portlabel.caddy"

rm -f "$CADDY_CONF"
rm -rf /etc/caddy/portlabel-fallback

if grep -q "import portlabel.caddy" "$CADDYFILE" 2>/dev/null; then
    tmp=$(mktemp)
    grep -v "import portlabel.caddy" "$CADDYFILE" | \
    grep -v "# portlabel — do not remove this line" > "$tmp"
    cp "$tmp" "$CADDYFILE"
    rm -f "$tmp"
fi

if grep -q "\[disabled by portlabel installer\]" "$CADDYFILE" 2>/dev/null; then
    tmp=$(mktemp)
    sed 's/^# \[disabled by portlabel installer\] //' "$CADDYFILE" > "$tmp"
    cp "$tmp" "$CADDYFILE"
    rm -f "$tmp"
fi

systemctl reload caddy > /dev/null 2>&1
print_success "Cleaned Caddy reverse proxy configurations"

read -rp "Remove saved domain configuration (/etc/portlabel)? (y/N): " del_data
if [[ "$del_data" == "y" || "$del_data" == "Y" ]]; then
    rm -rf /etc/portlabel
    print_success "Removed /etc/portlabel"
fi

echo -e "\n${GREEN}PortLabel completely uninstalled.${RESET}\n"