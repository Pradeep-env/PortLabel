#!/bin/bash

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
echo -e "  ${BOLD}PortLabel v1.0 Installer${RESET}"
echo "  ─────────────────────────────────"
echo ""

if [[ "$EUID" -ne 0 ]]; then
    print_error "Please run installer with sudo."
    exit 1
fi

# Ensure running from repo root
if [[ ! -f "bin/portlabel" || ! -d "core" || ! -d "web" ]]; then
    print_error "Installer must be run from the root of the PortLabel repository."
    exit 1
fi

echo -e "  ${BOLD}Step 1: Caddy Reverse Proxy${RESET}"

if command -v caddy &>/dev/null; then
    print_success "Caddy already installed — $(caddy version)"
else
    print_info "Installing Caddy..."
    if command -v apt &>/dev/null; then
        apt install -y debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null 2>&1
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
        apt update > /dev/null 2>&1
        apt install -y caddy > /dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y 'dnf-command(copr)' > /dev/null 2>&1
        dnf copr enable -y @caddy/caddy > /dev/null 2>&1
        dnf install -y caddy > /dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm caddy > /dev/null 2>&1
    else
        print_error "Unsupported package manager. Please install Caddy manually."
        exit 1
    fi

    if command -v caddy &>/dev/null; then
        print_success "Caddy installed successfully"
    else
        print_error "Caddy installation failed."
        exit 1
    fi
fi

echo ""
echo -e "  ${BOLD}Step 2: Caddy & Fallback Page Setup${RESET}"

CADDY_CONF="/etc/caddy/portlabel.caddy"
CADDYFILE="/etc/caddy/Caddyfile"
FALLBACK_DIR="/etc/caddy/portlabel-fallback"

touch "$CADDY_CONF"
mkdir -p "$FALLBACK_DIR"

if [[ -f "assets/fallback.html" ]]; then
    cp assets/fallback.html "$FALLBACK_DIR/fallback.html"
    print_success "Installed fallback error page to $FALLBACK_DIR"
elif [[ -f "fallback.html" ]]; then
    cp fallback.html "$FALLBACK_DIR/fallback.html"
    print_success "Installed fallback error page to $FALLBACK_DIR"
else
    print_warn "fallback.html not found; skipping fallback page."
fi

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
fi

if ! grep -q "import portlabel.caddy" "$CADDYFILE" 2>/dev/null; then
    echo "" >> "$CADDYFILE"
    echo "# portlabel — do not remove this line" >> "$CADDYFILE"
    echo "import portlabel.caddy" >> "$CADDYFILE"
    print_success "Added portlabel import to $CADDYFILE"
fi

systemctl enable caddy > /dev/null 2>&1
systemctl restart caddy > /dev/null 2>&1

echo ""
echo -e "  ${BOLD}Step 3: Core & CLI Installation${RESET}"

LIB_DIR="/usr/local/lib/portlabel"
mkdir -p "$LIB_DIR/core" "$LIB_DIR/web/templates" "/etc/portlabel"

cp core/storage.sh "$LIB_DIR/core/"
cp core/engine.sh "$LIB_DIR/core/"
cp web/app.py "$LIB_DIR/web/"
cp web/templates/index.html "$LIB_DIR/web/templates/"

chmod 755 "$LIB_DIR/core/"*.sh
chmod 755 "$LIB_DIR/web/app.py"

cp bin/portlabel /usr/local/bin/portlabel
chmod +x /usr/local/bin/portlabel
print_success "Installed CLI command: /usr/local/bin/portlabel"

echo ""
echo -e "  ${BOLD}Step 4: Web Dashboard Service${RESET}"

cat <<EOF > /etc/systemd/system/portlabel-web.service
[Unit]
Description=PortLabel Web Dashboard & API
After=network.target caddy.service

[Service]
Type=simple
User=root
WorkingDirectory=${LIB_DIR}/web
ExecStart=/usr/bin/python3 ${LIB_DIR}/web/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable portlabel-web > /dev/null 2>&1
systemctl restart portlabel-web > /dev/null 2>&1
print_success "Enabled & started portlabel-web.service (listening on port 2999)"

portlabel add portlabel 2999 > /dev/null 2>&1

echo ""
echo "  ─────────────────────────────────"
echo -e "  ${GREEN}${BOLD}PortLabel v1.0 installed successfully!${RESET}"
echo ""
echo -e "  CLI Usage:       ${CYAN}sudo portlabel${RESET}"
echo -e "  Web Dashboard:   ${CYAN}http://portlabel.local${RESET} (or http://localhost:2999)"
echo ""