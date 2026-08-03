#!/usr/bin/env bash
set -euo pipefail

# Read connection args from env using configured keys.
_mysql_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USERNAME:-root}"
    local pass="${DB_PASSWORD:-}"
    local args="-h$host -P$port -u$user"
    [[ -n "$pass" ]] && args="$args -p$pass"
    echo "$args"
}

db_mysql_available() {
    command_exists mysql && command_exists mysqldump
}

db_mysql_exists() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "SHOW DATABASES LIKE '$target';" | mysql $args | grep -q "$target"
}

db_mysql_create() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "CREATE DATABASE IF NOT EXISTS \`$target\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | mysql $args
}

db_mysql_drop() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "DROP DATABASE IF EXISTS \`$target\`;" | mysql $args
}

db_mysql_clone() {
    local source="$1"
    local target="$2"
    local args
    args="$(_mysql_args)"
    mysqldump --single-transaction $args "$source" | mysql $args "$target"
}
