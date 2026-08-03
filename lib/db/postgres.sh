#!/usr/bin/env bash
set -euo pipefail

_pg_conn_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-5432}"
    local user="${DB_USERNAME:-$USER}"
    local pass="${DB_PASSWORD:-}"
    local args="--host=$host --port=$port --username=$user"
    [[ -n "$pass" ]] && export PGPASSWORD="$pass"
    echo "$args"
}

db_postgres_available() {
    command_exists psql && command_exists pg_dump && command_exists createdb
}

db_postgres_exists() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    psql $args -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$target'" | grep -q "1"
}

db_postgres_create() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    createdb $args "$target"
}

db_postgres_drop() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    psql $args -d postgres -c "DROP DATABASE IF EXISTS \"$target\";"
}

db_postgres_clone() {
    local source="$1"
    local target="$2"
    local args
    args="$(_pg_conn_args)"
    pg_dump $args "$source" | psql $args -d "$target"
}
