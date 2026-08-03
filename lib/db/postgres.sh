#!/usr/bin/env bash
set -euo pipefail

_pg_conn_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-5432}"
    local user="${DB_USERNAME:-$USER}"
    echo "--host=$host --port=$port --username=$user"
}

# Run a postgres command with connection settings from the environment.
# Uses PGPASSWORD so the password is never visible in process listings.
_with_pg_env() {
    local pass="${DB_PASSWORD:-}"
    PGPASSWORD="$pass" "$@"
}

db_postgres_available() {
    command_exists psql && command_exists pg_dump && command_exists createdb
}

db_postgres_exists() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    _with_pg_env psql $args -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$target'" | grep -q "1"
}

db_postgres_create() {
    local target="$1"
    local dry_run="${2:-}"
    local args
    args="$(_pg_conn_args)"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would create Postgres database: $target"
        return 0
    fi
    _with_pg_env createdb $args "$target"
}

db_postgres_drop() {
    local target="$1"
    local dry_run="${2:-}"
    local args
    args="$(_pg_conn_args)"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would drop Postgres database: $target"
        return 0
    fi
    _with_pg_env psql $args -d postgres -c "DROP DATABASE IF EXISTS \"$target\";"
}

db_postgres_clone() {
    local source="$1"
    local target="$2"
    local dry_run="${3:-}"
    local args
    args="$(_pg_conn_args)"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would clone Postgres database: $source -> $target"
        return 0
    fi
    _with_pg_env pg_dump $args "$source" | _with_pg_env psql $args -d "$target"
}
