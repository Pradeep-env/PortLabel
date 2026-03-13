#!/bin/bash

# ============================================================
#  Portlabel uninstaller
#  Removes portlabel and optionally removes Caddy
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_success() { echo -e "  ${GREEN}✔${RESET} $1"; }
print_error()   { echo -e "  ${RED}✘${RESET} $1"; }
print_warn()    { echo -e "  ${YELLOW}!${RESET} $1"; }
print_info()    { echo -e "  ${CYAN}→${RESET} $1"; }

echo ""
echo -e "  ${BOLD}Portlabel Uninstaller${RESET}"
echo "  ─────────────────────────────────"
echo ""

if [[ "$EUID" -ne 0 ]]; then
    print_error "Please run uninstaller with sudo."
    exit 1
fi

echo -e "  ${YELLOW}This will remove Portlabel and clean up all related config.${RESET}"
echo ""
read -rp "  Continue? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "  Cancelled."
    exit 0
fi

echo ""

# ============================================================
#  STEP 1 — Remove portlabel block from /etc/hosts
# ============================================================

echo -e "  ${BOLD}Step 1: /etc/hosts${RESET}"

if grep -q "# portlabel-start" /etc/hosts; then
    tmp=$(mktemp)
    awk '
        /# portlabel-start/ { skip=1 }
        !skip { print }
        /# portlabel-end/ { skip=0 }
    ' /etc/hosts > "$tmp"
    cp "$tmp" /etc/hosts
    rm -f "$tmp"
    print_success "Removed portlabel block from /etc/hosts"
else
    print_info "No portlabel block found in /etc/hosts"
fi

# ============================================================
#  STEP 2 — Remove portlabel binary
# ============================================================

echo ""
echo -e "  ${BOLD}Step 2: Portlabel command${RESET}"

if [[ -f /usr/local/bin/portlabel ]]; then
    rm /usr/local/bin/portlabel
    print_success "Removed /usr/local/bin/portlabel"
else
    print_info "Portlabel command not found — skipping"
fi

# ============================================================
#  STEP 3 — Remove saved domain data
# ============================================================

echo ""
echo -e "  ${BOLD}Step 3: Domain data${RESET}"

read -rp "  Delete saved domain data (~/.portlabel)? (y/N): " del_data
if [[ "$del_data" == "y" || "$del_data" == "Y" ]]; then
    rm -rf "$HOME/.portlabel"
    print_success "Removed ~/.portlabel"
else
    print_warn "Kept ~/.portlabel — delete manually if needed"
fi

# ============================================================
#  STEP 4 — Clean up Caddy
# ============================================================

echo ""
echo -e "  ${BOLD}Step 4: Caddy${RESET}"

CADDYFILE="/etc/caddy/Caddyfile"
CADDY_CONF="/etc/caddy/portlabel.caddy"

# Always remove portlabel.caddy
if [[ -f "$CADDY_CONF" ]]; then
    rm -f "$CADDY_CONF"
    print_success "Removed $CADDY_CONF"
else
    print_info "No portlabel.caddy file found — skipping"
fi

# Remove fallback page directory
if [[ -d "/etc/caddy/portlabel-fallback" ]]; then
    rm -rf "/etc/caddy/portlabel-fallback"
    print_success "Removed /etc/caddy/portlabel-fallback"
fi

# Always remove the import line from Caddyfile
if grep -q "import portlabel.caddy" "$CADDYFILE" 2>/dev/null; then
    tmp=$(mktemp)
    grep -v "import portlabel.caddy" "$CADDYFILE" | \
    grep -v "# portlabel — do not remove this line" > "$tmp"
    cp "$tmp" "$CADDYFILE"
    rm -f "$tmp"
    print_success "Removed portlabel import from $CADDYFILE"
fi

# Restore the commented-out :80 block if portlabel installer disabled it
if grep -q "\[disabled by portlabel installer\]" "$CADDYFILE" 2>/dev/null; then
    tmp=$(mktemp)
    sed 's/^# \[disabled by portlabel installer\] //' "$CADDYFILE" > "$tmp"
    cp "$tmp" "$CADDYFILE"
    rm -f "$tmp"
    print_success "Restored default :80 block in $CADDYFILE"
fi

# Ask whether to fully uninstall Caddy
echo ""
read -rp "  Fully uninstall Caddy from the system? (y/N): " del_caddy
if [[ "$del_caddy" == "y" || "$del_caddy" == "Y" ]]; then
    systemctl stop caddy > /dev/null 2>&1
    systemctl disable caddy > /dev/null 2>&1

    if command -v apt &>/dev/null; then
        apt remove -y caddy > /dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf remove -y caddy > /dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        pacman -R --noconfirm caddy > /dev/null 2>&1
    else
        print_warn "Could not detect package manager. Remove Caddy manually."
    fi

    if ! command -v caddy &>/dev/null; then
        print_success "Caddy uninstalled"
    else
        print_warn "Caddy may not have been fully removed. Check manually."
    fi
else
    # Just reload Caddy with the cleaned config
    if systemctl is-active --quiet caddy; then
        systemctl reload caddy > /dev/null 2>&1
        print_success "Caddy reloaded with portlabel config removed"
    fi
    print_warn "Caddy kept — portlabel config has been cleaned from it"
fi

# ============================================================
#  DONE
# ============================================================

echo ""
echo "  ─────────────────────────────────"
echo -e "  ${GREEN}${BOLD}Portlabel uninstalled successfully.${RESET}"
echo ""
