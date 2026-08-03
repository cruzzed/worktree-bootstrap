#!/usr/bin/env bash
set -euo pipefail

port_in_use() {
    local port="$1"
    (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null
}

# Compute ports for an offset. base and result are associative array names.
compute_ports() {
    local offset="$1"
    local -n base_ref="$2"
    local -n result_ref="$3"
    local key
    for key in "${!base_ref[@]}"; do
        result_ref[$key]=$(( base_ref[$key] + offset ))
    done
}

# Return 0 if all checked ports for an offset are free.
offset_ports_available() {
    local offset="$1"
    local -n avail_base_ref="$2"
    local check_redis="$3"
    local check_mailhog="$4"
    local -A ports
    compute_ports "$offset" avail_base_ref ports

    local key
    for key in app db vite serve; do
        if port_in_use "${ports[$key]}"; then
            return 1
        fi
    done
    if [[ "$check_redis" == "1" ]] && port_in_use "${ports[redis]:-6379}"; then
        return 1
    fi
    if [[ "$check_mailhog" == "1" ]] && port_in_use "${ports[mailhog]:-1025}"; then
        return 1
    fi
    return 0
}

# Escape a string for safe use in a POSIX extended regular expression.
regex_escape() {
    sed -E 's/[][\\^$.*+?{}|()]/\\&/g' <<< "$1"
}

# Allocate an offset for a branch. Echoes the offset.
allocate_offset() {
    local registry_file="$1"
    local branch="$2"
    local -n alloc_base_ref="$3"
    local check_redis="$4"
    local check_mailhog="$5"

    mkdir -p "$(dirname "$registry_file")"
    touch "$registry_file"

    # Reuse existing offset for this branch.
    local escaped_branch existing
    escaped_branch="$(regex_escape "$branch")"
    existing="$(grep -E "^${escaped_branch}"$'\t' "$registry_file" 2>/dev/null | head -n1 | cut -f2)"
    if [[ -n "$existing" && "$existing" =~ ^[0-9]+$ ]]; then
        echo "$existing"
        return 0
    fi

    # Collect all registered offsets.
    local offsets=()
    local line off
    while IFS=$'\t' read -r _ off _ _; do
        [[ "$off" =~ ^[0-9]+$ ]] && offsets+=("$off")
    done < "$registry_file"

    # Try to reclaim a free registered offset.
    while IFS= read -r off; do
        [[ -z "$off" ]] && continue
        if offset_ports_available "$off" alloc_base_ref "$check_redis" "$check_mailhog"; then
            echo "$off"
            return 0
        fi
    done < <(printf '%s\n' "${offsets[@]}" | sort -n -u)

    # Allocate new offset above the highest registered one.
    local max_offset=0
    for off in "${offsets[@]}"; do
        (( off > max_offset )) && max_offset=$off
    done

    local off=$((max_offset + 1))
    while [[ $off -le 1000 ]]; do
        if offset_ports_available "$off" alloc_base_ref "$check_redis" "$check_mailhog"; then
            echo "$off"
            return 0
        fi
        off=$((off + 1))
    done

    fatal "could not find a free offset after 1000 attempts"
}

# Register or update a branch entry in the registry.
# Signature: register_offset <registry_file> <branch> <offset> <db_name> [dry_run]
# When dry_run is "1", writes are skipped and the function returns silently.
register_offset() {
    local registry_file="$1"
    local branch="$2"
    local offset="$3"
    local db_name="$4"
    local dry_run="${5:-0}"

    if [[ "$dry_run" == "1" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$registry_file")"
    touch "$registry_file"

    local escaped_branch tmp
    escaped_branch="$(regex_escape "$branch")"
    tmp="$(mktemp)"
    grep -vE "^${escaped_branch}"$'\t' "$registry_file" > "$tmp" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\n' "$branch" "$offset" "$db_name" "$(date -Iseconds)" >> "$tmp"
    mv "$tmp" "$registry_file"
}
