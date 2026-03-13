#!/bin/bash

# Portlabel installer

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run installer with sudo.${RESET}"
    exit 1
fi

echo "Installing Portlabel..."

cp portlabel.sh /usr/local/bin/portlabel
chmod +x /usr/local/bin/portlabel

echo -e "${GREEN}✔ Portlabel installed. Run: sudo portlabel${RESET}"
