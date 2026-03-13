#!/bin/bash

# ============================================================
#  Portlabel installer
#  Installs portlabel as a system command and sets up Caddy
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
echo -e "  ${BOLD}Portlabel Installer${RESET}"
echo "  ─────────────────────────────────"
echo ""

# --- Must run as root ---
if [[ "$EUID" -ne 0 ]]; then
    print_error "Please run installer with sudo."
    exit 1
fi

# --- Check portlabel.sh exists ---
if [[ ! -f "portlabel.sh" ]]; then
    print_error "portlabel.sh not found. Run this from the project directory."
    exit 1
fi

# ============================================================
#  STEP 1 — Install Caddy
# ============================================================

echo -e "  ${BOLD}Step 1: Caddy${RESET}"

if command -v caddy &>/dev/null; then
    print_success "Caddy already installed — $(caddy version)"
else
    print_info "Installing Caddy..."

    if command -v apt &>/dev/null; then
        apt install -y debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null 2>&1
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
        apt update > /dev/null 2>&1
        apt install -y caddy > /dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y 'dnf-command(copr)' > /dev/null 2>&1
        dnf copr enable -y @caddy/caddy > /dev/null 2>&1
        dnf install -y caddy > /dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm caddy > /dev/null 2>&1
    else
        print_error "Could not detect package manager. Install Caddy manually: https://caddyserver.com/docs/install"
        exit 1
    fi

    if command -v caddy &>/dev/null; then
        print_success "Caddy installed successfully"
    else
        print_error "Caddy installation failed. Install it manually and re-run."
        exit 1
    fi
fi

# ============================================================
#  STEP 2 — Create portlabel Caddy config file
# ============================================================

echo ""
echo -e "  ${BOLD}Step 2: Caddy config${RESET}"

CADDY_CONF="/etc/caddy/portlabel.caddy"
CADDYFILE="/etc/caddy/Caddyfile"

# Create empty portlabel config file
touch "$CADDY_CONF"
print_success "Created $CADDY_CONF"

# Disable the default Caddy catch-all :80 block
# It intercepts all traffic and serves Caddy's hello page,
# overriding portlabel's named .local blocks
if grep -q "^:80" "$CADDYFILE" 2>/dev/null; then
    tmp=$(mktemp)
    awk '
        /^:80[[:space:]]*\{/ { skip=1; print "# [disabled by portlabel installer] " $0; next }
        skip && /^\}/ { skip=0; print "# [disabled by portlabel installer] " $0; next }
        skip { print "# [disabled by portlabel installer] " $0; next }
        { print }
    ' "$CADDYFILE" > "$tmp"
    cp "$tmp" "$CADDYFILE"
    rm -f "$tmp"
    print_success "Disabled default :80 catch-all block in $CADDYFILE"
else
    print_success "No default :80 block found — nothing to disable"
fi

# Tell Caddy's main Caddyfile to import the portlabel config
if ! grep -q "import portlabel.caddy" "$CADDYFILE" 2>/dev/null; then
    echo "" >> "$CADDYFILE"
    echo "# portlabel — do not remove this line" >> "$CADDYFILE"
    echo "import portlabel.caddy" >> "$CADDYFILE"
    print_success "Added portlabel import to $CADDYFILE"
else
    print_success "portlabel import already present in $CADDYFILE"
fi

# ============================================================
#  STEP 3 — Enable and start Caddy
# ============================================================

echo ""
echo -e "  ${BOLD}Step 3: Caddy service${RESET}"

systemctl enable caddy > /dev/null 2>&1
systemctl start caddy > /dev/null 2>&1

if systemctl is-active --quiet caddy; then
    print_success "Caddy is running"
else
    print_warn "Caddy failed to start. Check: sudo systemctl status caddy"
fi

# ============================================================
#  STEP 4 — Install portlabel command
# ============================================================

echo ""
echo -e "  ${BOLD}Step 4: Portlabel command${RESET}"

cp portlabel.sh /usr/local/bin/portlabel
chmod +x /usr/local/bin/portlabel
print_success "Installed: /usr/local/bin/portlabel"

# ============================================================
#  DONE
# ============================================================

echo ""
echo "  ─────────────────────────────────"
echo -e "  ${GREEN}${BOLD}Installation complete.${RESET}"
echo ""
echo -e "  Run ${CYAN}sudo portlabel${RESET} to get started."
echo ""
echo -e "  ${YELLOW}Note:${RESET} If Chrome ignores .local domains, disable async DNS:"
echo "  chrome://flags/#enable-async-dns  →  set to Disabled"
echo ""
