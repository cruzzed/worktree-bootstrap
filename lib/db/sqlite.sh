#!/usr/bin/env bash
set -euo pipefail

db_sqlite_available() {
    command_exists sqlite3
}

db_sqlite_exists() {
    local target="$1"
    [[ -f "$target" ]]
}

db_sqlite_create() {
    local target="$1"
    sqlite3 "$target" "VACUUM;"
}

db_sqlite_drop() {
    local target="$1"
    local dry_run="${2:-}"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would drop SQLite database file: $target"
        return 0
    fi
    rm -f "$target"
}

db_sqlite_clone() {
    local source="$1"
    local target="$2"
    local dry_run="${3:-}"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would clone SQLite database file: $source -> $target"
        return 0
    fi
    cp "$source" "$target"
}
