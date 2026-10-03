#!/bin/bash

# ============================================================
#  PortLabel - Local Domain Manager
#  Assigns .local domain names to self-hosted services
#  https://github.com/Pradeep-env/PortLabel.git
# ============================================================

# --- Config paths ---
CONF_DIR="$HOME/.portlabel"
CONF_FILE="$CONF_DIR/domains.conf"
HOSTS_FILE="/etc/hosts"
HOSTS_MARKER_START="# portlabel-start — do not edit manually"
HOSTS_MARKER_END="# portlabel-end"
CADDY_CONF="/etc/caddy/portlabel.caddy"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ============================================================
#  INIT
# ============================================================

init() {
    mkdir -p "$CONF_DIR"
    touch "$CONF_FILE"

    # Create portlabel block in hosts file if it doesn't exist
    if ! grep -q "$HOSTS_MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        echo "" | sudo tee -a "$HOSTS_FILE" > /dev/null
        echo "$HOSTS_MARKER_START" | sudo tee -a "$HOSTS_FILE" > /dev/null
        echo "$HOSTS_MARKER_END" | sudo tee -a "$HOSTS_FILE" > /dev/null
    fi
}

# ============================================================
#  HELPERS
# ============================================================

print_header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ██████╗  ██████╗ ██████╗ ████████╗██╗      █████╗ ██████╗ ███████╗██╗     "
    echo "  ██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔══██╗██╔════╝██║     "
    echo "  ██████╔╝██║   ██║██████╔╝   ██║   ██║     ███████║██████╔╝█████╗  ██║     "
    echo "  ██╔═══╝ ██║   ██║██╔══██╗   ██║   ██║     ██╔══██║██╔══██╗██╔══╝  ██║     "
    echo "  ██║     ╚██████╔╝██║  ██║   ██║   ███████╗██║  ██║██████╔╝███████╗███████╗"
    echo "  ╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝"
    echo -e "${RESET}"
    echo -e "  ${CYAN}Local Domain Manager${RESET} — assign .local names to your self-hosted services"
    echo ""
}

print_success() { echo -e "  ${GREEN}✔${RESET} $1"; }
print_error()   { echo -e "  ${RED}✘${RESET} $1"; }
print_warn()    { echo -e "  ${YELLOW}!${RESET} $1"; }
print_info()    { echo -e "  ${CYAN}→${RESET} $1"; }

pause() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

domain_exists() {
    grep -q "^$1|" "$CONF_FILE" 2>/dev/null
}

port_in_use() {
    grep -q "|$1|" "$CONF_FILE" 2>/dev/null
}

# ============================================================
#  HOSTS FILE MANAGEMENT
# ============================================================

# Rebuild the portlabel block in /etc/hosts from conf file
sync_hosts() {
    local tmp
    tmp=$(mktemp)

    # Write everything outside the portlabel block
    awk "
        /$HOSTS_MARKER_START/ { skip=1 }
        !skip { print }
        /$HOSTS_MARKER_END/ { skip=0 }
    " "$HOSTS_FILE" > "$tmp"

    # Append fresh portlabel block
    echo "$HOSTS_MARKER_START" >> "$tmp"
    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "127.0.0.1 ${name}.local" >> "$tmp"
        else
            echo "#127.0.0.1 ${name}.local  [disabled]" >> "$tmp"
        fi
    done < "$CONF_FILE"
    echo "$HOSTS_MARKER_END" >> "$tmp"

    sudo cp "$tmp" "$HOSTS_FILE"
    rm -f "$tmp"
}

# ============================================================
#  CADDY MANAGEMENT
# ============================================================

# Rebuild /etc/caddy/portlabel.caddy from conf file
sync_caddy() {
    local tmp
    tmp=$(mktemp)

    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "${name}.local {" >> "$tmp"
            echo "    tls internal" >> "$tmp"
            echo "    reverse_proxy localhost:${port} {" >> "$tmp"
            echo "        health_uri /" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "    handle_errors 502 503 {" >> "$tmp"
            echo "        root * /etc/caddy/portlabel-fallback" >> "$tmp"
            echo "        rewrite * /fallback.html" >> "$tmp"
            echo "        file_server" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "}" >> "$tmp"
            echo "" >> "$tmp"
        fi
    done < "$CONF_FILE"

    sudo cp "$tmp" "$CADDY_CONF"
    rm -f "$tmp"
}

# Reload Caddy to apply config changes
reload_caddy() {
    if systemctl is-active --quiet caddy; then
        sudo systemctl reload caddy
    else
        print_warn "Caddy is not running. Start it with: sudo systemctl start caddy"
    fi
}

# ============================================================
#  CORE OPERATIONS
# ============================================================

create_domain() {
    echo -e "\n  ${BOLD}Create a new .local domain${RESET}\n"

    read -rp "  Service name (e.g. n8n, nextcloud): " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if [[ -z "$name" ]]; then
        print_error "Name cannot be empty."
        pause; return
    fi

    if domain_exists "$name"; then
        print_error "${name}.local already exists. Use Modify to change it."
        pause; return
    fi

    read -rp "  Port number: " port

    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        print_error "Invalid port. Must be a number between 1 and 65535."
        pause; return
    fi

    if port_in_use "$port"; then
        print_warn "Port $port is already assigned to another service."
        read -rp "  Continue anyway? (y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { pause; return; }
    fi

    echo "${name}|${port}|enabled" >> "$CONF_FILE"
    sync_hosts
    sync_caddy
    reload_caddy

    print_success "Created: ${name}.local → localhost:${port}"
    pause
}

list_domains() {
    echo -e "\n  ${BOLD}Registered Domains${RESET}\n"

    if [[ ! -s "$CONF_FILE" ]]; then
        print_warn "No domains registered yet. Use Create to add one."
        pause; return
    fi

    printf "  ${BOLD}%-20s %-8s %-25s %-10s${RESET}\n" "Service" "Port" "Address" "Status"
    echo "  ────────────────────────────────────────────────────────────"

    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            status_colored="${GREEN}enabled${RESET}"
        else
            status_colored="${RED}disabled${RESET}"
        fi
        printf "  %-20s %-8s %-25s " "$name" "$port" "${name}.local"
        echo -e "$status_colored"
    done < "$CONF_FILE"

    echo ""
    pause
}

modify_domain() {
    echo -e "\n  ${BOLD}Modify a domain${RESET}\n"

    if [[ ! -s "$CONF_FILE" ]]; then
        print_warn "No domains registered yet."
        pause; return
    fi

    list_names
    read -rp "  Enter service name to modify: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! domain_exists "$name"; then
        print_error "${name}.local not found."
        pause; return
    fi

    current_port=$(grep "^${name}|" "$CONF_FILE" | cut -d'|' -f2)
    read -rp "  New port [current: ${current_port}]: " new_port

    if [[ -z "$new_port" ]]; then
        print_warn "No changes made."
        pause; return
    fi

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
        print_error "Invalid port."
        pause; return
    fi

    # Update in conf file
    sed -i "s/^${name}|${current_port}|/${name}|${new_port}|/" "$CONF_FILE"
    sync_hosts
    sync_caddy
    reload_caddy

    print_success "Updated: ${name}.local → localhost:${new_port}"
    pause
}

delete_domain() {
    echo -e "\n  ${BOLD}Delete a domain${RESET}\n"

    if [[ ! -s "$CONF_FILE" ]]; then
        print_warn "No domains registered yet."
        pause; return
    fi

    list_names
    read -rp "  Enter service name to delete: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! domain_exists "$name"; then
        print_error "${name}.local not found."
        pause; return
    fi

    read -rp "  Delete ${name}.local? This cannot be undone. (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warn "Cancelled."
        pause; return
    fi

    sed -i "/^${name}|/d" "$CONF_FILE"
    sync_hosts
    sync_caddy
    reload_caddy

    print_success "Deleted: ${name}.local"
    pause
}

toggle_domain() {
    echo -e "\n  ${BOLD}Toggle a domain (enable / disable)${RESET}\n"

    if [[ ! -s "$CONF_FILE" ]]; then
        print_warn "No domains registered yet."
        pause; return
    fi

    list_names
    read -rp "  Enter service name to toggle: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! domain_exists "$name"; then
        print_error "${name}.local not found."
        pause; return
    fi

    current_status=$(grep "^${name}|" "$CONF_FILE" | cut -d'|' -f3)

    if [[ "$current_status" == "enabled" ]]; then
        sed -i "s/^${name}|\(.*\)|enabled$/${name}|\1|disabled/" "$CONF_FILE"
        sync_hosts
        sync_caddy
        reload_caddy
        print_success "${name}.local is now disabled"
    else
        sed -i "s/^${name}|\(.*\)|disabled$/${name}|\1|enabled/" "$CONF_FILE"
        sync_hosts
        sync_caddy
        reload_caddy
        print_success "${name}.local is now enabled"
    fi

    pause
}

# ============================================================
#  UTILITY
# ============================================================

list_names() {
    echo -e "  ${CYAN}Available services:${RESET}"
    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        echo "    - ${name} (${name}.local:${port}) [${status}]"
    done < "$CONF_FILE"
    echo ""
}

# ============================================================
#  MAIN MENU
# ============================================================

main_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}Main Menu${RESET}\n"
        echo "    1) Create   — add a new .local domain"
        echo "    2) List     — view all registered domains"
        echo "    3) Modify   — change a port"
        echo "    4) Delete   — remove a domain"
        echo "    5) Toggle   — enable or disable a domain"
        echo "    6) Exit"
        echo ""
        read -rp "  Select an option [1-6]: " choice

        case "$choice" in
            1) create_domain ;;
            2) list_domains ;;
            3) modify_domain ;;
            4) delete_domain ;;
            5) toggle_domain ;;
            6)
                echo ""
                print_info "Goodbye."
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid option. Please enter 1–6."
                sleep 1
                ;;
        esac
    done
}

# ============================================================
#  ENTRY POINT
# ============================================================

# Must run as sudo for /etc/hosts access
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Portlabel requires sudo to manage /etc/hosts.${RESET}"
    echo "Run: sudo portlabel"
    exit 1
fi

init
main_menu
