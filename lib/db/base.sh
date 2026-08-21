#!/usr/bin/env bash
set -euo pipefail

# Dispatch a call to the configured DB driver. Unknown drivers fail cleanly
# instead of producing a "command not found" error.
db_call() {
    local driver="$1"
    local fn="$2"
    shift 2
    if ! declare -F "db_${driver}_${fn}" >/dev/null; then
        if [[ "$fn" == "available" || "$fn" == "exists" ]]; then
            return 1
        fi
        fatal "unknown database driver: $driver (use mysql, sqlite, postgres, none, or database.create/drop commands)"
    fi
    "db_${driver}_${fn}" "$@"
}

db_driver_available() {
    local driver="$1"
    declare -F "db_${driver}_available" >/dev/null || return 1
    db_call "$driver" available
}

db_exists() {
    local driver="$1"
    local target="$2"
    db_call "$driver" exists "$target"
}

db_create() {
    local driver="$1"
    local target="$2"
    db_call "$driver" create "$target"
}

db_drop() {
    local driver="$1"
    local target="$2"
    local dry_run="${3:-}"
    db_call "$driver" drop "$target" "$dry_run"
}

db_clone() {
    local driver="$1"
    local source="$2"
    local target="$3"
    local dry_run="${4:-}"
    db_call "$driver" clone "$source" "$target" "$dry_run"
}
