#!/usr/bin/env bash
set -euo pipefail

# Run a mysql/mysqldump command with connection settings from the environment.
# The mysql client ignores MYSQL_USER, so host/port/user go via CLI args.
# MYSQL_PWD is still used so the password is never visible in process listings.
_with_mysql_env() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USERNAME:-root}"
    local pass="${DB_PASSWORD:-}"
    MYSQL_PWD="$pass" "$@" --host="$host" --port="$port" --user="$user"
}

# Escape a database name for safe use as a MySQL quoted identifier.
_mysql_quote_id() {
    local name="$1"
    # Backticks inside identifiers are escaped by doubling them.
    printf '`%s`' "${name//\`/\`\`}"
}

# Escape a value for safe use inside a single-quoted SQL string literal.
_mysql_like_literal() {
    local value="$1"
    # Escape backslash first, then single quote.
    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf '%s' "$value"
}

db_mysql_available() {
    command_exists mysql && command_exists mysqldump
}

db_mysql_exists() {
    local target="$1"
    echo "SHOW DATABASES LIKE '$(_mysql_like_literal "$target")';" \
        | _with_mysql_env mysql \
        | grep -qx "$target" \
        || return 1
}

db_mysql_create() {
    local target="$1"
    echo "CREATE DATABASE IF NOT EXISTS $(_mysql_quote_id "$target") CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
        | _with_mysql_env mysql
}

db_mysql_drop() {
    local target="$1"
    local dry_run="${2:-}"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would drop MySQL database: $target"
        return 0
    fi
    echo "DROP DATABASE IF EXISTS $(_mysql_quote_id "$target");" \
        | _with_mysql_env mysql
}

db_mysql_clone() {
    local source="$1"
    local target="$2"
    local dry_run="${3:-}"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would clone MySQL database: $source -> $target"
        return 0
    fi
    _with_mysql_env mysqldump --single-transaction "$source" \
        | _with_mysql_env mysql "$target"
}
