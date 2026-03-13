#!/bin/bash

# Portlabel uninstaller

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run uninstaller with sudo.${RESET}"
    exit 1
fi

echo ""
echo -e "${YELLOW}This will remove Portlabel and clean up /etc/hosts.${RESET}"
read -rp "Continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

# Remove portlabel block from /etc/hosts
if grep -q "# portlabel-start" /etc/hosts; then
    tmp=$(mktemp)
    awk '
        /# portlabel-start/ { skip=1 }
        !skip { print }
        /# portlabel-end/ { skip=0 }
    ' /etc/hosts > "$tmp"
    cp "$tmp" /etc/hosts
    rm -f "$tmp"
    echo -e "${GREEN}✔ Removed portlabel block from /etc/hosts${RESET}"
fi

# Remove binary
if [[ -f /usr/local/bin/portlabel ]]; then
    rm /usr/local/bin/portlabel
    echo -e "${GREEN}✔ Removed /usr/local/bin/portlabel${RESET}"
fi

# Ask about conf data
echo ""
read -rp "Also delete saved domain data (~/.portlabel)? (y/N): " del_data
if [[ "$del_data" == "y" || "$del_data" == "Y" ]]; then
    rm -rf "$HOME/.portlabel"
    echo -e "${GREEN}✔ Removed ~/.portlabel${RESET}"
else
    echo -e "${YELLOW}! Kept ~/.portlabel — delete manually if needed${RESET}"
fi

echo ""
echo -e "${GREEN}Portlabel uninstalled.${RESET}"
