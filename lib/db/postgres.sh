#!/usr/bin/env bash
set -euo pipefail

# Default database used for maintenance queries such as existence checks,
# CREATE DATABASE, and DROP DATABASE. Override with PG_MAINTENANCE_DB.
: "${PG_MAINTENANCE_DB:=postgres}"

_pg_conn_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-5432}"
    local user="${DB_USERNAME:-${USER:-postgres}}"
    echo "--host=$host --port=$port --username=$user"
}

# Run a postgres command with connection settings from the environment.
# Uses PGPASSWORD so the password is never visible in process listings.
_with_pg_env() {
    local pass="${DB_PASSWORD:-}"
    PGPASSWORD="$pass" "$@"
}

# Escape a database name for safe use as a PostgreSQL quoted identifier.
_pg_quote_id() {
    local name="$1"
    # Double quotes inside identifiers are escaped by doubling them.
    printf '"%s"' "${name//\"/\"\"}"
}

# Escape a value for safe use inside a single-quoted SQL string literal.
_pg_like_literal() {
    local value="$1"
    # PostgreSQL escapes single quotes by doubling them.
    printf '%s' "${value//\'/\'\'}"
}

db_postgres_available() {
    command_exists psql && command_exists pg_dump
}

db_postgres_exists() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    _with_pg_env psql $args -d "$PG_MAINTENANCE_DB" -tAc "SELECT 1 FROM pg_database WHERE datname='$(_pg_like_literal "$target")'" | grep -q "1"
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
    _with_pg_env psql $args -d "$PG_MAINTENANCE_DB" -c "CREATE DATABASE $(_pg_quote_id "$target");"
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
    _with_pg_env psql $args -d "$PG_MAINTENANCE_DB" -c "DROP DATABASE IF EXISTS $(_pg_quote_id "$target");"
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
