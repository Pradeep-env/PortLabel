#!/bin/bash

# ============================================================
#  Portlabel Dev — Developer Port Reserve & Service Manager
#  Companion script to Portlabel
#  Run: sudo ./devmode.sh
#  https://github.com/yourusername/portlabel
# ============================================================

# --- Shared config paths (must match portlabel.sh) ---
CONF_DIR="$HOME/.portlabel"
CONF_FILE="$CONF_DIR/domains.conf"
DEV_CONF="$CONF_DIR/dev.conf"
HOSTS_FILE="/etc/hosts"
HOSTS_MARKER_START="# portlabel-start — do not edit manually"
HOSTS_MARKER_END="# portlabel-end"
CADDY_CONF="/etc/caddy/portlabel.caddy"
FALLBACK_DIR="/etc/caddy/portlabel-fallback"
SERVICE_DIR="/etc/systemd/system"

# --- Dev port range ---
DEV_PORT_MIN=30000
DEV_PORT_MAX=39999

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# ============================================================
#  HELPERS
# ============================================================

print_header() {
    clear
    echo -e "${BOLD}${MAGENTA}"
    echo "  ██████╗ ███████╗██╗   ██╗    ███╗   ███╗ ██████╗ ██████╗ ███████╗"
    echo "  ██╔══██╗██╔════╝██║   ██║    ████╗ ████║██╔═══██╗██╔══██╗██╔════╝"
    echo "  ██║  ██║█████╗  ██║   ██║    ██╔████╔██║██║   ██║██║  ██║█████╗  "
    echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝    ██║╚██╔╝██║██║   ██║██║  ██║██╔══╝  "
    echo "  ██████╔╝███████╗ ╚████╔╝     ██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗"
    echo "  ╚═════╝ ╚══════╝  ╚═══╝      ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝"
    echo -e "${RESET}"
    echo -e "  ${MAGENTA}Portlabel Dev${RESET} — port reserve & service manager for developers"
    echo ""
}

print_success() { echo -e "  ${GREEN}✔${RESET} $1"; }
print_error()   { echo -e "  ${RED}✘${RESET} $1"; }
print_warn()    { echo -e "  ${YELLOW}!${RESET} $1"; }
print_info()    { echo -e "  ${CYAN}→${RESET} $1"; }
print_dev()     { echo -e "  ${MAGENTA}⬡${RESET} $1"; }

pause() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

dev_exists() {
    grep -q "^[^|]*|$1|" "$DEV_CONF" 2>/dev/null
}

name_taken() {
    grep -q "|$1|" "$CONF_FILE" 2>/dev/null || grep -q "^[^|]*|$1|" "$DEV_CONF" 2>/dev/null
}

# ============================================================
#  INIT
# ============================================================

init() {
    mkdir -p "$CONF_DIR"
    touch "$CONF_FILE"
    touch "$DEV_CONF"

    if ! grep -q "$HOSTS_MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        echo "" >> "$HOSTS_FILE"
        echo "$HOSTS_MARKER_START" >> "$HOSTS_FILE"
        echo "$HOSTS_MARKER_END" >> "$HOSTS_FILE"
    fi
}

# ============================================================
#  PORT RESERVATION
# ============================================================

find_free_port() {
    for port in $(seq "$DEV_PORT_MIN" "$DEV_PORT_MAX"); do
        # Not in use by OS
        if ! ss -ltn 2>/dev/null | grep -q ":${port} "; then
            # Not already reserved in dev.conf
            if ! grep -q "|${port}|" "$DEV_CONF" 2>/dev/null; then
                # Not assigned in domains.conf
                if ! grep -q "|${port}|" "$CONF_FILE" 2>/dev/null; then
                    echo "$port"
                    return
                fi
            fi
        fi
    done
    echo ""
}

# ============================================================
#  HOSTS + CADDY SYNC
# ============================================================

sync_hosts() {
    local tmp
    tmp=$(mktemp)

    awk -v start="$HOSTS_MARKER_START" -v end="$HOSTS_MARKER_END" '
        $0 == start { skip=1 }
        !skip { print }
        $0 == end { skip=0 }
    ' "$HOSTS_FILE" > "$tmp"

    echo "$HOSTS_MARKER_START" >> "$tmp"

    # Main domains
    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "127.0.0.1 ${name}.local" >> "$tmp"
        else
            echo "#127.0.0.1 ${name}.local  [disabled]" >> "$tmp"
        fi
    done < "$CONF_FILE"

    # Dev domains
    while IFS='|' read -r type name port stack path status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "127.0.0.1 ${name}.local  # dev" >> "$tmp"
        else
            echo "#127.0.0.1 ${name}.local  # dev [disabled]" >> "$tmp"
        fi
    done < "$DEV_CONF"

    echo "$HOSTS_MARKER_END" >> "$tmp"
    cp "$tmp" "$HOSTS_FILE"
    rm -f "$tmp"
}

sync_caddy() {
    local tmp
    tmp=$(mktemp)

    # Main domains
    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "${name}.local {" >> "$tmp"
            echo "    tls internal" >> "$tmp"
            echo "    reverse_proxy localhost:${port} {" >> "$tmp"
            echo "        health_uri /" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "    handle_errors 502 503 {" >> "$tmp"
            echo "        root * ${FALLBACK_DIR}" >> "$tmp"
            echo "        rewrite * /fallback.html" >> "$tmp"
            echo "        file_server" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "}" >> "$tmp"
            echo "" >> "$tmp"
        fi
    done < "$CONF_FILE"

    # Dev domains
    while IFS='|' read -r type name port stack path status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "${name}.local {" >> "$tmp"
            echo "    tls internal" >> "$tmp"
            echo "    reverse_proxy localhost:${port} {" >> "$tmp"
            echo "        health_uri /" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "    handle_errors 502 503 {" >> "$tmp"
            echo "        root * ${FALLBACK_DIR}" >> "$tmp"
            echo "        rewrite * /fallback.html" >> "$tmp"
            echo "        file_server" >> "$tmp"
            echo "    }" >> "$tmp"
            echo "}" >> "$tmp"
            echo "" >> "$tmp"
        fi
    done < "$DEV_CONF"

    cp "$tmp" "$CADDY_CONF"
    rm -f "$tmp"
}

reload_caddy() {
    if systemctl is-active --quiet caddy; then
        systemctl reload caddy
    else
        print_warn "Caddy is not running. Start it: sudo systemctl start caddy"
    fi
}

# ============================================================
#  SERVICE FILE GENERATOR
# ============================================================

get_stack_command() {
    local stack="$1"
    local path="$2"
    local port="$3"
    local extra="$4"   # e.g. python venv path or jar name

    case "$stack" in
        react|vite)
            echo "ExecStart=/usr/bin/npm run dev -- --port ${port}"
            ;;
        next)
            echo "ExecStart=/usr/bin/env PORT=${port} /usr/bin/npm run dev"
            ;;
        flask)
            if [[ -n "$extra" && -f "${extra}/bin/python" ]]; then
                echo "ExecStart=${extra}/bin/python -m flask run --port ${port} --host 0.0.0.0"
            else
                echo "ExecStart=/usr/bin/python3 -m flask run --port ${port} --host 0.0.0.0"
            fi
            ;;
        fastapi)
            if [[ -n "$extra" && -f "${extra}/bin/uvicorn" ]]; then
                echo "ExecStart=${extra}/bin/uvicorn main:app --port ${port} --host 0.0.0.0 --reload"
            else
                echo "ExecStart=/usr/bin/uvicorn main:app --port ${port} --host 0.0.0.0 --reload"
            fi
            ;;
        spring)
            local jar="${extra:-app.jar}"
            echo "ExecStart=/usr/bin/java -jar ${path}/${jar} --server.port=${port}"
            ;;
        static)
            echo "ExecStart=/usr/bin/caddy file-server --listen :${port} --root ${path}"
            ;;
        *)
            echo ""
            ;;
    esac
}

generate_service_file() {
    local name="$1"
    local stack="$2"
    local path="$3"
    local port="$4"
    local extra="$5"
    local service_file="${SERVICE_DIR}/portlabel-${name}.service"

    local exec_start
    exec_start=$(get_stack_command "$stack" "$path" "$port" "$extra")

    if [[ -z "$exec_start" ]]; then
        print_error "Could not generate service command for stack: $stack"
        return 1
    fi

    # Determine user for service
    local real_user="${SUDO_USER:-$USER}"

    cat > "$service_file" <<EOF
# Generated by Portlabel Dev
# Project : ${name}
# Stack   : ${stack}
# Domain  : https://${name}.local
# Port    : ${port}

[Unit]
Description=Portlabel Dev — ${name} (${stack})
After=network.target

[Service]
Type=simple
User=${real_user}
WorkingDirectory=${path}
${exec_start}
Restart=on-failure
RestartSec=5
Environment=PORT=${port}
Environment=NODE_ENV=development

[Install]
WantedBy=multi-user.target
EOF

    echo "$service_file"
}

# ============================================================
#  CORE OPERATIONS
# ============================================================

create_project() {
    echo -e "\n  ${BOLD}Reserve a port and create a dev project${RESET}\n"

    # Project name
    read -rp "  Project name (e.g. myapp, api, frontend): " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if [[ -z "$name" ]]; then
        print_error "Name cannot be empty."
        pause; return
    fi

    if name_taken "$name"; then
        print_error "${name} is already taken in Portlabel or Dev."
        pause; return
    fi

    # Project type
    echo ""
    echo -e "  ${BOLD}Project type:${RESET}"
    echo "    1) frontend"
    echo "    2) backend"
    echo "    3) fullstack"
    echo ""
    read -rp "  Select [1-3]: " type_choice
    case "$type_choice" in
        1) type="frontend" ;;
        2) type="backend" ;;
        3) type="fullstack" ;;
        *) print_error "Invalid choice."; pause; return ;;
    esac

    # Stack
    echo ""
    echo -e "  ${BOLD}Stack:${RESET}"
    echo "    1) React / Vite"
    echo "    2) Next.js"
    echo "    3) Flask"
    echo "    4) FastAPI"
    echo "    5) Spring Boot"
    echo "    6) Static HTML"
    echo ""
    read -rp "  Select [1-6]: " stack_choice
    case "$stack_choice" in
        1) stack="react" ;;
        2) stack="next" ;;
        3) stack="flask" ;;
        4) stack="fastapi" ;;
        5) stack="spring" ;;
        6) stack="static" ;;
        *) print_error "Invalid choice."; pause; return ;;
    esac

    # Project path
    echo ""
    read -rp "  Full project path (e.g. /home/user/projects/myapp): " proj_path
    if [[ ! -d "$proj_path" ]]; then
        print_warn "Directory not found: $proj_path"
        read -rp "  Continue anyway? (y/N): " cont
        [[ "$cont" != "y" && "$cont" != "Y" ]] && { pause; return; }
    fi

    # Extra info per stack
    extra=""
    if [[ "$stack" == "flask" || "$stack" == "fastapi" ]]; then
        echo ""
        read -rp "  Python venv path (leave blank to use system python): " venv_path
        extra="$venv_path"
    elif [[ "$stack" == "spring" ]]; then
        echo ""
        read -rp "  JAR filename (e.g. app.jar): " jar_name
        extra="$jar_name"
    fi

    # Auto-assign port
    echo ""
    print_info "Finding a free port in range ${DEV_PORT_MIN}–${DEV_PORT_MAX}..."
    port=$(find_free_port)

    if [[ -z "$port" ]]; then
        print_error "No free ports available in the dev range. This should not happen."
        pause; return
    fi

    print_success "Reserved port: ${port}"

    # Create service file?
    echo ""
    read -rp "  Create systemd service file to run on startup? (Y/n): " make_service
    service_created=false

    if [[ "$make_service" != "n" && "$make_service" != "N" ]]; then
        service_file=$(generate_service_file "$name" "$stack" "$proj_path" "$port" "$extra")
        if [[ $? -eq 0 ]]; then
            systemctl daemon-reload
            systemctl enable "portlabel-${name}.service" > /dev/null 2>&1
            service_created=true
            print_success "Service file created: $service_file"
            print_success "Service enabled on startup"
        fi
    fi

    # Write to dev.conf
    echo "${type}|${name}|${port}|${stack}|${proj_path}|enabled" >> "$DEV_CONF"

    # Register in main domains.conf with [dev] tag
    echo "${name}|${port}|enabled|dev" >> "$CONF_FILE"

    # Sync everything
    sync_hosts
    sync_caddy
    reload_caddy

    echo ""
    echo -e "  ${BOLD}${GREEN}Project registered:${RESET}"
    echo ""
    print_dev "Domain  : https://${name}.local"
    print_dev "Port    : ${port} (auto-reserved)"
    print_dev "Stack   : ${stack}"
    print_dev "Type    : ${type}"
    if $service_created; then
        print_dev "Service : portlabel-${name}.service"
        echo ""
        print_info "Start now: sudo systemctl start portlabel-${name}"
    fi
    echo ""
    echo -e "  ${CYAN}CORS — allow origin:${RESET}  https://${name}.local"
    echo -e "  ${CYAN}API base URL:${RESET}         https://${name}.local"
    echo ""

    pause
}

list_projects() {
    echo -e "\n  ${BOLD}Registered Dev Projects${RESET}\n"

    if [[ ! -s "$DEV_CONF" ]]; then
        print_warn "No dev projects registered yet. Use Create to add one."
        pause; return
    fi

    printf "  ${BOLD}%-12s %-20s %-8s %-12s %-10s %-10s${RESET}\n" \
        "Type" "Name" "Port" "Stack" "Status" "Service"
    echo "  ────────────────────────────────────────────────────────────────────"

    while IFS='|' read -r type name port stack path status; do
        [[ -z "$name" ]] && continue

        if [[ "$status" == "enabled" ]]; then
            status_col="${GREEN}enabled${RESET}"
        else
            status_col="${RED}disabled${RESET}"
        fi

        if systemctl is-active --quiet "portlabel-${name}" 2>/dev/null; then
            svc_col="${GREEN}running${RESET}"
        elif systemctl is-enabled --quiet "portlabel-${name}" 2>/dev/null; then
            svc_col="${YELLOW}stopped${RESET}"
        else
            svc_col="${RED}none${RESET}"
        fi

        printf "  %-12s %-20s %-8s %-12s " "$type" "${name}.local" "$port" "$stack"
        echo -e "${status_col}     ${svc_col}"
    done < "$DEV_CONF"

    echo ""
    pause
}

toggle_project() {
    echo -e "\n  ${BOLD}Toggle a dev project (enable / disable)${RESET}\n"

    if [[ ! -s "$DEV_CONF" ]]; then
        print_warn "No dev projects registered yet."
        pause; return
    fi

    list_dev_names
    read -rp "  Enter project name to toggle: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! dev_exists "$name"; then
        print_error "${name} not found in dev projects."
        pause; return
    fi

    current_status=$(grep "|${name}|" "$DEV_CONF" | cut -d'|' -f6)

    if [[ "$current_status" == "enabled" ]]; then
        sed -i "s/|\(${name}\)|\([^|]*\)|\([^|]*\)|\([^|]*\)|enabled$/|\1|\2|\3|\4|disabled/" "$DEV_CONF"
        sed -i "s/^${name}|\([^|]*\)|enabled|dev$/${name}|\1|disabled|dev/" "$CONF_FILE"
        systemctl stop "portlabel-${name}" > /dev/null 2>&1
        sync_hosts; sync_caddy; reload_caddy
        print_success "${name}.local is now disabled"
    else
        sed -i "s/|\(${name}\)|\([^|]*\)|\([^|]*\)|\([^|]*\)|disabled$/|\1|\2|\3|\4|enabled/" "$DEV_CONF"
        sed -i "s/^${name}|\([^|]*\)|disabled|dev$/${name}|\1|enabled|dev/" "$CONF_FILE"
        systemctl start "portlabel-${name}" > /dev/null 2>&1
        sync_hosts; sync_caddy; reload_caddy
        print_success "${name}.local is now enabled"
    fi

    pause
}

service_control() {
    echo -e "\n  ${BOLD}Service Control${RESET}\n"

    if [[ ! -s "$DEV_CONF" ]]; then
        print_warn "No dev projects registered yet."
        pause; return
    fi

    list_dev_names
    read -rp "  Enter project name: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! dev_exists "$name"; then
        print_error "${name} not found."
        pause; return
    fi

    if [[ ! -f "${SERVICE_DIR}/portlabel-${name}.service" ]]; then
        print_warn "No service file found for ${name}."
        read -rp "  Create one now? (Y/n): " make_it
        if [[ "$make_it" != "n" && "$make_it" != "N" ]]; then
            local stack path port extra
            stack=$(grep "|${name}|" "$DEV_CONF" | cut -d'|' -f4)
            path=$(grep  "|${name}|" "$DEV_CONF" | cut -d'|' -f5)
            port=$(grep  "|${name}|" "$DEV_CONF" | cut -d'|' -f3)
            generate_service_file "$name" "$stack" "$path" "$port" ""
            systemctl daemon-reload
            systemctl enable "portlabel-${name}.service" > /dev/null 2>&1
            print_success "Service file created and enabled"
        fi
        pause; return
    fi

    echo ""
    echo -e "  ${BOLD}Service: portlabel-${name}${RESET}\n"
    echo "    1) Start"
    echo "    2) Stop"
    echo "    3) Restart"
    echo "    4) View status"
    echo "    5) View logs"
    echo "    6) Back"
    echo ""
    read -rp "  Select [1-6]: " svc_choice

    case "$svc_choice" in
        1) systemctl start "portlabel-${name}" && print_success "Started" ;;
        2) systemctl stop  "portlabel-${name}" && print_success "Stopped" ;;
        3) systemctl restart "portlabel-${name}" && print_success "Restarted" ;;
        4) echo ""; systemctl status "portlabel-${name}" --no-pager ;;
        5) echo ""; journalctl -u "portlabel-${name}" -n 30 --no-pager ;;
        6) return ;;
        *) print_error "Invalid option." ;;
    esac

    pause
}

delete_project() {
    echo -e "\n  ${BOLD}Delete a dev project${RESET}\n"

    if [[ ! -s "$DEV_CONF" ]]; then
        print_warn "No dev projects registered yet."
        pause; return
    fi

    list_dev_names
    read -rp "  Enter project name to delete: " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if ! dev_exists "$name"; then
        print_error "${name} not found."
        pause; return
    fi

    read -rp "  Delete ${name}.local and release its port? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_warn "Cancelled."; pause; return; }

    # Stop and remove service
    if [[ -f "${SERVICE_DIR}/portlabel-${name}.service" ]]; then
        systemctl stop    "portlabel-${name}" > /dev/null 2>&1
        systemctl disable "portlabel-${name}" > /dev/null 2>&1
        rm -f "${SERVICE_DIR}/portlabel-${name}.service"
        systemctl daemon-reload
        print_success "Service removed"
    fi

    # Remove from dev.conf and domains.conf
    sed -i "/|${name}|/d" "$DEV_CONF"
    sed -i "/^${name}|/d" "$CONF_FILE"

    sync_hosts
    sync_caddy
    reload_caddy

    print_success "Deleted: ${name}.local — port released"
    pause
}

show_cors_info() {
    echo -e "\n  ${BOLD}CORS & API Reference${RESET}\n"

    if [[ ! -s "$DEV_CONF" ]]; then
        print_warn "No dev projects registered yet."
        pause; return
    fi

    while IFS='|' read -r type name port stack path status; do
        [[ -z "$name" ]] && continue
        echo -e "  ${MAGENTA}${name}.local${RESET}  [${stack}] [${type}]"
        echo -e "    Domain    : https://${name}.local"
        echo -e "    Port      : ${port}"

        case "$stack" in
            react|vite|next|static)
                echo -e "    CORS allow: ${CYAN}(set on your backend — this is a frontend)${RESET}"
                ;;
            flask)
                echo -e "    CORS allow: ${CYAN}CORS(app, origins=[\"https://${name}.local\"])${RESET}"
                ;;
            fastapi)
                echo -e "    CORS allow: ${CYAN}allow_origins=[\"https://${name}.local\"]${RESET}"
                ;;
            spring)
                echo -e "    CORS allow: ${CYAN}@CrossOrigin(origins = \"https://${name}.local\")${RESET}"
                ;;
        esac

        echo ""
    done < "$DEV_CONF"

    pause
}

# ============================================================
#  UTILITY
# ============================================================

list_dev_names() {
    echo -e "  ${MAGENTA}Registered dev projects:${RESET}"
    while IFS='|' read -r type name port stack path status; do
        [[ -z "$name" ]] && continue
        echo "    - ${name} (${name}.local) [${stack}] [${status}]"
    done < "$DEV_CONF"
    echo ""
}

# ============================================================
#  MAIN MENU
# ============================================================

main_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}Main Menu${RESET}\n"
        echo "    1) Create    — reserve a port and register a dev project"
        echo "    2) List      — view all dev projects"
        echo "    3) Toggle    — enable or disable a project"
        echo "    4) Services  — start / stop / restart / logs"
        echo "    5) CORS info — view domain, port and CORS snippets"
        echo "    6) Delete    — remove a project and release its port"
        echo "    7) Exit"
        echo ""
        read -rp "  Select an option [1-7]: " choice

        case "$choice" in
            1) create_project ;;
            2) list_projects ;;
            3) toggle_project ;;
            4) service_control ;;
            5) show_cors_info ;;
            6) delete_project ;;
            7)
                echo ""
                print_info "Goodbye."
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid option. Please enter 1–7."
                sleep 1
                ;;
        esac
    done
}

# ============================================================
#  ENTRY POINT
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Portlabel Dev requires sudo.${RESET}"
    echo "Run: sudo ./devmode.sh"
    exit 1
fi

init
main_menu
