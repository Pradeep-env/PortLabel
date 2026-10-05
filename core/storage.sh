#!/bin/bash
#  PortLabel — Storage Layer (core/storage.sh)
#  Handles atomic CRUD operations on /etc/portlabel/domains.conf


PORTLABEL_DIR="/etc/portlabel"
PORTLABEL_CONF="${PORTLABEL_DIR}/domains.conf"

storage_init() {
    if [[ ! -d "$PORTLABEL_DIR" ]]; then
        mkdir -p "$PORTLABEL_DIR"
        chmod 755 "$PORTLABEL_DIR"
    fi

    if [[ ! -f "$PORTLABEL_CONF" ]]; then
        touch "$PORTLABEL_CONF"
        chmod 644 "$PORTLABEL_CONF"
    fi
}

storage_get_all() {
    [[ ! -f "$PORTLABEL_CONF" ]] && return 0
    awk -F'|' 'NF >= 3 { print $1 "|" $2 "|" $3 }' "$PORTLABEL_CONF"
}

storage_get_by_name() {
    local target="$1"
    [[ -z "$target" || ! -f "$PORTLABEL_CONF" ]] && return 1
    awk -F'|' -v name="$target" '$1 == name && NF >= 3 { print $1 "|" $2 "|" $3; found=1; exit } END { exit !found }' "$PORTLABEL_CONF"
}

storage_get_by_port() {
    local target="$1"
    [[ -z "$target" || ! -f "$PORTLABEL_CONF" ]] && return 1
    awk -F'|' -v port="$target" '$2 == port && NF >= 3 { print $1 "|" $2 "|" $3; found=1; exit } END { exit !found }' "$PORTLABEL_CONF"
}

storage_add() {
    local name="$1"
    local port="$2"
    local status="${3:-enabled}"

    storage_init

    if storage_get_by_name "$name" >/dev/null 2>&1; then
        return 1
    fi

    echo "${name}|${port}|${status}" >> "$PORTLABEL_CONF"
    return 0
}

storage_update_port() {
    local target_name="$1"
    local new_port="$2"

    [[ ! -f "$PORTLABEL_CONF" ]] && return 1

    local tmp
    tmp=$(mktemp "${PORTLABEL_DIR}/domains.tmp.XXXXXX") || return 1

    local found=0
    while IFS='|' read -r name port status rest; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$target_name" ]]; then
            echo "${name}|${new_port}|${status}" >> "$tmp"
            found=1
        else
            echo "${name}|${port}|${status}" >> "$tmp"
        fi
    done < "$PORTLABEL_CONF"

    if [[ $found -eq 1 ]]; then
        mv "$tmp" "$PORTLABEL_CONF"
        chmod 644 "$PORTLABEL_CONF"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

storage_toggle_status() {
    local target_name="$1"

    [[ ! -f "$PORTLABEL_CONF" ]] && return 1

    local tmp
    tmp=$(mktemp "${PORTLABEL_DIR}/domains.tmp.XXXXXX") || return 1

    local found=0
    local new_status=""
    while IFS='|' read -r name port status rest; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$target_name" ]]; then
            if [[ "$status" == "enabled" ]]; then
                new_status="disabled"
            else
                new_status="enabled"
            fi
            echo "${name}|${port}|${new_status}" >> "$tmp"
            found=1
        else
            echo "${name}|${port}|${status}" >> "$tmp"
        fi
    done < "$PORTLABEL_CONF"

    if [[ $found -eq 1 ]]; then
        mv "$tmp" "$PORTLABEL_CONF"
        chmod 644 "$PORTLABEL_CONF"
        echo "$new_status"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

storage_remove() {
    local target_name="$1"

    [[ ! -f "$PORTLABEL_CONF" ]] && return 1

    local tmp
    tmp=$(mktemp "${PORTLABEL_DIR}/domains.tmp.XXXXXX") || return 1

    local found=0
    while IFS='|' read -r name port status rest; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$target_name" ]]; then
            found=1
            continue
        fi
        echo "${name}|${port}|${status}" >> "$tmp"
    done < "$PORTLABEL_CONF"

    if [[ $found -eq 1 ]]; then
        mv "$tmp" "$PORTLABEL_CONF"
        chmod 644 "$PORTLABEL_CONF"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}