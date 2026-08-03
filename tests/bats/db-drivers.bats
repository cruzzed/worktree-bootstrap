#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/base.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/mysql.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/sqlite.sh"

    export TMP_BIN="$(mktemp -d)"
    export PATH="$TMP_BIN:$PATH"
    export DB_PASSWORD="secret"
}

teardown() {
    rm -rf "$TMP_BIN"
}

@test "mysql driver detects availability of mysql and mysqldump" {
    if command -v mysql >/dev/null 2>&1 && command -v mysqldump >/dev/null 2>&1; then
        db_mysql_available
    else
        ! db_mysql_available
    fi
}

@test "mysql drop dry-run prints and does not execute" {
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
echo "mysql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysql"

    run db_mysql_drop "test_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would drop MySQL database: test_db"* ]]
}

@test "mysql clone dry-run prints and does not execute" {
    cat > "$TMP_BIN/mysqldump" <<'EOF'
#!/usr/bin/env bash
echo "mysqldump executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysqldump"
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
echo "mysql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysql"

    run db_mysql_clone "source_db" "target_db" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would clone MySQL database: source_db -> target_db"* ]]
}

@test "mysql connection uses environment variables, not -p argument" {
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
# Dump the environment keys that mysql received; exclude PATH-like noise.
env | grep -E '^MYSQL_' | sort
EOF
    chmod +x "$TMP_BIN/mysql"

    run _with_mysql_env mysql
    [ "$status" -eq 0 ]
    [[ "$output" == *"MYSQL_PWD=secret"* ]]
    [[ "$output" != *"-psecret"* ]]
}

@test "mysql commands quote database names safely" {
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
cat > "$TMP_MYSQL_INPUT"
EOF
    chmod +x "$TMP_BIN/mysql"
    export TMP_MYSQL_INPUT="$(mktemp)"

    local weird='db`name;$(whoami)'
    db_mysql_create "$weird"

    # The backtick in the name must be escaped by doubling it.
    [[ "$(cat "$TMP_MYSQL_INPUT")" == *'CREATE DATABASE IF NOT EXISTS `db``name;$(whoami)`'* ]]
    rm -f "$TMP_MYSQL_INPUT"
}

@test "mysql exists escapes single quotes in database names" {
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
cat > "$TMP_MYSQL_INPUT"
EOF
    chmod +x "$TMP_BIN/mysql"
    export TMP_MYSQL_INPUT="$(mktemp)"

    local weird="db's"
    db_mysql_exists "$weird" || true
    [[ "$(cat "$TMP_MYSQL_INPUT")" == *"SHOW DATABASES LIKE 'db\\'s';"* ]]
    rm -f "$TMP_MYSQL_INPUT"
}

@test "db_drop dispatcher passes dry-run to driver" {
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
echo "mysql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysql"

    run db_drop "mysql" "test_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would drop MySQL database: test_db"* ]]
}

@test "db_clone dispatcher passes dry-run to driver" {
    cat > "$TMP_BIN/mysqldump" <<'EOF'
#!/usr/bin/env bash
echo "mysqldump executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysqldump"
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
echo "mysql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/mysql"

    run db_clone "mysql" "source_db" "target_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would clone MySQL database: source_db -> target_db"* ]]
}

@test "sqlite driver clones a database file" {
    command -v sqlite3 >/dev/null 2>&1 || skip

    local src="$(mktemp).sqlite"
    local target="$(mktemp)_feature_test.sqlite"
    echo "CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (42);" | sqlite3 "$src"

    DB_SQLITE_SOURCE_PATH="$src"
    db_sqlite_clone "$src" "$target"
    [[ -f "$target" ]]

    local count
    count="$(sqlite3 "$target" 'SELECT COUNT(*) FROM t;')"
    [[ "$count" == "1" ]]

    rm -f "$src" "$target"
}
