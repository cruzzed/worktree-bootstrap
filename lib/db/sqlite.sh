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
    rm -f "$target"
}

db_sqlite_clone() {
    local source="$1"
    local target="$2"
    cp "$source" "$target"
}
