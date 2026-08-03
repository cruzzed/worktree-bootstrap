#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/base.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/mysql.sh"
}

@test "mysql driver detects availability of mysql and mysqldump" {
    if command -v mysql >/dev/null 2>&1 && command -v mysqldump >/dev/null 2>&1; then
        db_mysql_available
    else
        ! db_mysql_available
    fi
}
