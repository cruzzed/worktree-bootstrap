#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/base.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/mysql.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/postgres.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/sqlite.sh"

    export TMP_BIN="$(mktemp -d)"
    export TMP_TEST_DIR="$(mktemp -d)"
    export PATH="$TMP_BIN:$PATH"
    export DB_PASSWORD="secret"
}

teardown() {
    rm -rf "$TMP_BIN" "$TMP_TEST_DIR"
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
echo "ARGS: $*"
EOF
    chmod +x "$TMP_BIN/mysql"

    run _with_mysql_env mysql
    [ "$status" -eq 0 ]
    [[ "$output" == *"MYSQL_PWD=secret"* ]]
    [[ "$output" != *"-psecret"* ]]
    # mysql client ignores MYSQL_USER, so connection details must be CLI args
    [[ "$output" == *"ARGS: --host=127.0.0.1 --port=3306 --user=root"* ]]
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
    db_sqlite_available || skip

    local src="$TMP_TEST_DIR/source.sqlite"
    local target="$TMP_TEST_DIR/target.sqlite"
    echo "CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (42);" | sqlite3 "$src"

    db_sqlite_clone "$src" "$target"
    [[ -f "$target" ]]

    local count
    count="$(sqlite3 "$target" 'SELECT COUNT(*) FROM t;')"
    [[ "$count" == "1" ]]
}

@test "sqlite drop dry-run prints and does not execute" {
    local target="$TMP_TEST_DIR/drop_me.sqlite"
    touch "$target"

    run db_sqlite_drop "$target" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would drop SQLite database file: $target"* ]]
    [ -f "$target" ]
}

@test "sqlite clone dry-run prints and does not execute" {
    local src="$TMP_TEST_DIR/source.sqlite"
    local target="$TMP_TEST_DIR/target_clone.sqlite"
    touch "$src"

    run db_sqlite_clone "$src" "$target" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would clone SQLite database file: $src -> $target"* ]]
    [ ! -f "$target" ]
}

@test "postgres driver detects availability of psql and pg_dump" {
    if command -v psql >/dev/null 2>&1 && command -v pg_dump >/dev/null 2>&1; then
        db_postgres_available
    else
        ! db_postgres_available
    fi
}

@test "postgres connection uses PGPASSWORD environment variable" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
env | grep -E '^PGPASSWORD=' | sort
EOF
    chmod +x "$TMP_BIN/psql"

    run _with_pg_env psql
    [ "$status" -eq 0 ]
    [[ "$output" == *"PGPASSWORD=secret"* ]]
}

@test "postgres create dry-run prints and does not execute" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/psql"

    run db_postgres_create "test_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would create Postgres database: test_db"* ]]
}

@test "postgres drop dry-run prints and does not execute" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/psql"

    run db_postgres_drop "test_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would drop Postgres database: test_db"* ]]
}

@test "postgres clone dry-run prints and does not execute" {
    cat > "$TMP_BIN/pg_dump" <<'EOF'
#!/usr/bin/env bash
echo "pg_dump executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/pg_dump"
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/psql"

    run db_postgres_clone "source_db" "target_db" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would clone Postgres database: source_db -> target_db"* ]]
}

@test "postgres exists escapes single quotes in database names" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$TMP_PSQL_INPUT"
echo "1"
EOF
    chmod +x "$TMP_BIN/psql"
    export TMP_PSQL_INPUT="$(mktemp)"

    local weird="db's"
    run db_postgres_exists "$weird"
    [ "$status" -eq 0 ]
    [[ "$(cat "$TMP_PSQL_INPUT")" == *"WHERE datname='db''s'"* ]]
    rm -f "$TMP_PSQL_INPUT"
}

@test "postgres drop escapes double quotes in database names" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "$*"
EOF
    chmod +x "$TMP_BIN/psql"

    local weird='db"name'
    run db_postgres_drop "$weird"
    [ "$status" -eq 0 ]
    [[ "$output" == *'DROP DATABASE IF EXISTS "db""name"'* ]]
}

@test "postgres create escapes double quotes in database names" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "$*"
EOF
    chmod +x "$TMP_BIN/psql"

    local weird='db"name'
    run db_postgres_create "$weird"
    [ "$status" -eq 0 ]
    [[ "$output" == *'CREATE DATABASE "db""name"'* ]]
}

@test "postgres uses PG_MAINTENANCE_DB for maintenance database" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$TMP_PSQL_INPUT"
echo "1"
EOF
    chmod +x "$TMP_BIN/psql"
    export TMP_PSQL_INPUT="$(mktemp)"

    PG_MAINTENANCE_DB="template1" run db_postgres_exists "test_db"
    [ "$status" -eq 0 ]
    [[ "$(cat "$TMP_PSQL_INPUT")" == *"-d template1"* ]]
    rm -f "$TMP_PSQL_INPUT"
}

@test "postgres connection falls back to postgres when USER is unset" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$TMP_PSQL_INPUT"
echo "1"
EOF
    chmod +x "$TMP_BIN/psql"
    export TMP_PSQL_INPUT="$(mktemp)"

    unset USER DB_USERNAME
    run db_postgres_exists "test_db"
    [ "$status" -eq 0 ]
    [[ "$(cat "$TMP_PSQL_INPUT")" == *"--username=postgres"* ]]
    rm -f "$TMP_PSQL_INPUT"
}

@test "db_drop dispatcher passes dry-run to postgres driver" {
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/psql"

    run db_drop "postgres" "test_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would drop Postgres database: test_db"* ]]
}

@test "db_clone dispatcher passes dry-run to postgres driver" {
    cat > "$TMP_BIN/pg_dump" <<'EOF'
#!/usr/bin/env bash
echo "pg_dump executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/pg_dump"
    cat > "$TMP_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql executed" >&2
exit 1
EOF
    chmod +x "$TMP_BIN/psql"

    run db_clone "postgres" "source_db" "target_db" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would clone Postgres database: source_db -> target_db"* ]]
}

@test "db_driver_available returns 1 for unknown driver without error output" {
    run db_driver_available "_nope_driver"
    [ "$status" -eq 1 ]
    [[ "$output" != *"command not found"* ]]
}

@test "db_call fatals with a clear message for unknown driver" {
    run db_call "_nope_driver" create "x"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown database driver: _nope_driver"* ]]
}
