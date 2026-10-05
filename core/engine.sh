#!/bin/bash
#  PortLabel — Engine Layer (core/engine.sh)
#  Handles input validation, /etc/hosts, and Caddy synchronization

HOSTS_FILE="/etc/hosts"
HOSTS_MARKER_START="# portlabel-start — do not edit manually"
HOSTS_MARKER_END="# portlabel-end"
CADDY_CONF="/etc/caddy/portlabel.caddy"
FALLBACK_DIR="/etc/caddy/portlabel-fallback"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/storage.sh"

engine_validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
        return 1
    fi
    return 0
}

engine_validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        return 1
    fi
    return 0
}

engine_sync_hosts() {
    local tmp
    tmp=$(mktemp) || return 1

    if [[ -f "$HOSTS_FILE" ]]; then
        awk -v start="$HOSTS_MARKER_START" -v end="$HOSTS_MARKER_END" '
            $0 == start { skip=1 }
            !skip { print }
            $0 == end { skip=0 }
        ' "$HOSTS_FILE" > "$tmp"
    fi

    echo "$HOSTS_MARKER_START" >> "$tmp"
    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            echo "127.0.0.1 ${name}.local" >> "$tmp"
        else
            echo "#127.0.0.1 ${name}.local  [disabled]" >> "$tmp"
        fi
    done < <(storage_get_all)
    echo "$HOSTS_MARKER_END" >> "$tmp"

    cp "$tmp" "$HOSTS_FILE"
    chmod 644 "$HOSTS_FILE"
    rm -f "$tmp"
    return 0
}

engine_sync_caddy() {
    local tmp
    tmp=$(mktemp) || return 1

    while IFS='|' read -r name port status; do
        [[ -z "$name" ]] && continue
        if [[ "$status" == "enabled" ]]; then
            cat <<EOF >> "$tmp"
http://${name}.local {
    reverse_proxy localhost:${port}
    handle_errors 502 503 {
        root * ${FALLBACK_DIR}
        rewrite * /fallback.html
        file_server
    }
}


EOF
        fi
    done < <(storage_get_all)

    mkdir -p "$(dirname "$CADDY_CONF")"
    cp "$tmp" "$CADDY_CONF"
    chmod 644 "$CADDY_CONF"
    rm -f "$tmp"
    return 0
}

engine_reload_caddy() {
    if systemctl is-active --quiet caddy 2>/dev/null; then
        systemctl reload caddy >/dev/null 2>&1
        return $?
    fi
    return 2 
}

engine_apply_all() {
    engine_sync_hosts || return 1
    engine_sync_caddy || return 1
    engine_reload_caddy
    return 0
}