#!/usr/bin/env bats

setup() {
    export TMP_ORIGIN="$(mktemp -d)"
    export SCRIPT="$BATS_TEST_DIRNAME/../../worktree-bootstrap.sh"
    # Hermetic valet TLD detection: no machine config during tests.
    export VALET_CONFIG="/nonexistent/valet-config.json"
    cd "$TMP_ORIGIN"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -q -m "initial"
}

teardown() {
    # Remove every registered worktree (created either directly or by the
    # tool under shortened/custom names), then the origin itself.
    if [[ -d "$TMP_ORIGIN" ]]; then
        local wt
        git -C "$TMP_ORIGIN" worktree list --porcelain 2>/dev/null \
            | awk '/^worktree / {print $2}' \
            | while read -r wt; do
                [[ "$wt" == "$TMP_ORIGIN" ]] && continue
                git -C "$TMP_ORIGIN" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
            done
    fi
    rm -rf "$TMP_ORIGIN" "$(dirname "$TMP_ORIGIN")/wt-customdir"
}

@test "create prints dry-run report without errors" {
    git branch feature/smoke
    echo 'DB_DATABASE=main' > .env
    run "$SCRIPT" create feature/smoke --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create worktree"* ]]
    [[ "$output" == *"feature/smoke"* ]]
}

@test "bootstrap prints dry-run report from a worktree" {
    git branch feature/test
    cat > .worktree-bootstrap.yml <<'EOF'
database:
  driver: sqlite
  sqlite_source_path: main.sqlite
EOF
    echo 'DB_DATABASE=main.sqlite' > .env
    touch main.sqlite
    git worktree add -q "${TMP_ORIGIN}-feature-test" feature/test
    cd "${TMP_ORIGIN}-feature-test"
    run "$SCRIPT" bootstrap --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktree-bootstrap preflight"* ]]
    [[ "$output" == *"branch   : feature/test"* ]]
    [[ "$output" == *"would copy config files"* ]]
    [[ "$output" == *"would update .env and register offset"* ]]
    [[ "$output" == *"worktree-bootstrap report"* ]]
}

@test "destroy prints dry-run report without errors" {
    git branch feature/test
    run "$SCRIPT" destroy feature/test --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would destroy"* ]]
}

@test "destroy succeeds when .env exists without marker" {
    git branch feature/no-marker
    cat > .worktree-bootstrap.yml <<'EOF'
database:
  driver: sqlite
  sqlite_source_path: main.sqlite
EOF
    echo 'DB_DATABASE=main.sqlite' > .env
    touch main.sqlite
    git worktree add -q "${TMP_ORIGIN}-feature-no-marker" feature/no-marker
    cd "${TMP_ORIGIN}-feature-no-marker"
    run "$SCRIPT" destroy feature/no-marker
    [ "$status" -eq 0 ]
    [[ ! -d "${TMP_ORIGIN}-feature-no-marker" ]]
}

@test "bootstrap dry-run skips database driver availability checks" {
    git branch feature/dry-db
    cat > .worktree-bootstrap.yml <<'EOF'
database:
  driver: _nonexistent_probe_driver
EOF
    echo 'DB_DATABASE=main' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-dry-db" feature/dry-db
    cd "${TMP_ORIGIN}-feature-dry-db"
    run "$SCRIPT" bootstrap --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would create/clone database"* ]]
    [[ "$output" != *"driver not available"* ]]
}

@test "bootstrap applies env_updates with branch, slug, site and port templates" {
    git branch feature/env
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: sqlite
  sqlite_source_path: main.sqlite
env_updates:
  APP_URL: "https://{site}.test"
  CUSTOM_KEY: "{branch_slug}-{ports.app}"
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'DB_DATABASE=main.sqlite' > .env
    touch main.sqlite
    git worktree add -q "${TMP_ORIGIN}-feature-env" feature/env
    cd "${TMP_ORIGIN}-feature-env"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    local expected_site
    expected_site="$(basename "${TMP_ORIGIN}-feature-env" | tr '[:upper:]' '[:lower:]')"
    grep -qxF "APP_URL=https://${expected_site}.test" .env
    local offset app_port
    offset="$(grep -oE 'offset:[0-9]+' .env | cut -d: -f2)"
    app_port=$((8080 + offset))
    grep -qxF "CUSTOM_KEY=feature_env-${app_port}" .env
    grep -qxF "DB_DATABASE=${TMP_ORIGIN}-feature-env/wt_feature_env.sqlite" .env
    # env_updates is defined, so no built-in Laravel keys are written.
    ! grep -qE '^APP_PORT=' .env
    ! grep -qE '^FORWARD_DB_PORT=' .env
    ! grep -qE '^VITE_PORT=' .env
}

@test "destroy runs rendered commands.destroy hook before teardown" {
    git branch feature/destroy-hook
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: sqlite
  sqlite_source_path: main.sqlite
commands:
  install:
    - "true"
  build:
    - "true"
  destroy:
    - "touch destroyed-{site}"
YAML
    echo 'DB_DATABASE=main.sqlite' > .env
    touch main.sqlite
    git worktree add -q "${TMP_ORIGIN}-feature-destroy-hook" feature/destroy-hook
    cd "${TMP_ORIGIN}-feature-destroy-hook"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    cd "$TMP_ORIGIN"
    run "$SCRIPT" destroy feature/destroy-hook
    [ "$status" -eq 0 ]
    local expected_site
    expected_site="$(basename "${TMP_ORIGIN}-feature-destroy-hook" | tr '[:upper:]' '[:lower:]')"
    [[ -f "${TMP_ORIGIN}/destroyed-${expected_site}" ]]
    [[ ! -d "${TMP_ORIGIN}-feature-destroy-hook" ]]
}

@test "global flags are accepted in any position" {
    git branch feature/smoke
    echo 'DB_DATABASE=main' > .env
    run "$SCRIPT" create --dry-run feature/smoke
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create worktree"* ]]
    run "$SCRIPT" --dry-run destroy feature/smoke
    [ "$status" -eq 0 ]
    [[ "$output" == *"would destroy"* ]]
}

@test "create --dry-run renders the full bootstrap plan" {
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: sqlite
  sqlite_source_path: main.sqlite
env_updates:
  CUSTOM_KEY: "{branch_slug}-{ports.app}"
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'DB_DATABASE=main.sqlite' > .env
    run "$SCRIPT" create feature/plan --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create worktree"* ]]
    [[ "$output" == *"does not exist; would create from HEAD"* ]]
    [[ "$output" == *"worktree-bootstrap preflight"* ]]
    [[ "$output" == *"branch   : feature/plan"* ]]
    [[ "$output" == *"driver   : sqlite"* ]]
    [[ "$output" == *"[dry-run] env: CUSTOM_KEY=feature_plan-"* ]]
    [[ "$output" == *"[dry-run] would run: true"* ]]
    [[ "$output" == *"worktree-bootstrap report"* ]]
    # Dry-run must not create the port registry.
    [[ ! -e .worktree-bootstrap/ports.tsv ]]
}

@test "bootstrap fails fast when a hook script is missing from the worktree" {
    git branch feature/missing-hook
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
commands:
  install:
    - "scripts/setup.sh"
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-missing-hook" feature/missing-hook
    cd "${TMP_ORIGIN}-feature-missing-hook"
    run "$SCRIPT" bootstrap
    [ "$status" -ne 0 ]
    [[ "$output" == *"hook script not found in worktree: scripts/setup.sh"* ]]
}

@test "destroy prunes the worktree so the branch is immediately deletable" {
    git branch feature/prune
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-prune" feature/prune
    cd "${TMP_ORIGIN}-feature-prune"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    cd "$TMP_ORIGIN"
    run "$SCRIPT" destroy feature/prune
    [ "$status" -eq 0 ]
    [[ ! -d "${TMP_ORIGIN}-feature-prune" ]]
    # No manual git worktree prune needed before deleting the branch.
    git branch -D feature/prune
}

@test "destroy --delete-branch removes the branch" {
    git branch feature/delbr
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-delbr" feature/delbr
    cd "$TMP_ORIGIN"
    run "$SCRIPT" destroy --delete-branch feature/delbr
    [ "$status" -eq 0 ]
    [[ ! -d "${TMP_ORIGIN}-feature-delbr" ]]
    ! git show-ref --verify --quiet refs/heads/feature/delbr
}

@test "database.create/drop commands replace driver dispatch" {
    git branch feature/dbcmd
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
  create: "touch {worktree_root}/db-created-{branch_slug}"
  drop: "touch {main_repo}/db-dropped-{branch_slug}"
env_updates:
  DB_NAME: "{db_name}"
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-dbcmd" feature/dbcmd
    cd "${TMP_ORIGIN}-feature-dbcmd"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    [[ -f "db-created-feature_dbcmd" ]]
    grep -qxF "DB_NAME=wt_feature_dbcmd" .env
    # Command-based provisioning owns its env: no built-in DB_DATABASE write.
    ! grep -qE '^DB_DATABASE=' .env
    cd "$TMP_ORIGIN"
    run "$SCRIPT" destroy feature/dbcmd
    [ "$status" -eq 0 ]
    [[ -f "${TMP_ORIGIN}/db-dropped-feature_dbcmd" ]]
}

@test "driver none skips the database step silently" {
    git branch feature/nodb
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-nodb" feature/nodb
    cd "${TMP_ORIGIN}-feature-nodb"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    [[ "$output" == *"database ............ skipped (disabled)"* ]]
    [[ "$output" != *"command not found"* ]]
    ! grep -qE '^DB_DATABASE=' .env
    cd "$TMP_ORIGIN"
    run "$SCRIPT" destroy feature/nodb
    [ "$status" -eq 0 ]
    [[ "$output" != *"command not found"* ]]
}

@test "create reads DB credentials from main .env before worktree .env exists" {
    git branch feature/mysql-create
    cat > .worktree-bootstrap.yml <<'YAML'
copy_from_main:
  - .env
database:
  driver: mysql
  source_env_key: DB_DATABASE
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'DB_DATABASE=main_production_db' > .env

    export TMP_BIN="$(mktemp -d)"
    export PATH="$TMP_BIN:$PATH"
    export MYSQLDUMP_ARGS="$(mktemp)"
    cat > "$TMP_BIN/mysqldump" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$MYSQLDUMP_ARGS"
echo "-- mock dump"
EOF
    cat > "$TMP_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
EOF
    chmod +x "$TMP_BIN/mysqldump" "$TMP_BIN/mysql"

    run "$SCRIPT" create feature/mysql-create
    [ "$status" -eq 0 ]
    # The fresh worktree has no .env until copy_from_main seeds it mid-run;
    # mysqldump must still receive the source db from the main repo .env.
    [[ "$(cat "$MYSQLDUMP_ARGS")" == *"--single-transaction main_production_db"* ]]
    rm -rf "$TMP_BIN" "$MYSQLDUMP_ARGS"
}

@test "unknown driver warns cleanly and reports the skip" {
    git branch feature/bogus
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: _bogus_driver
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    echo 'X=1' > .env
    git worktree add -q "${TMP_ORIGIN}-feature-bogus" feature/bogus
    cd "${TMP_ORIGIN}-feature-bogus"
    run "$SCRIPT" bootstrap
    [ "$status" -eq 0 ]
    [[ "$output" == *"_bogus_driver driver not available"* ]]
    [[ "$output" != *"command not found"* ]]
    [[ "$output" == *"database ............ skipped (_bogus_driver driver not available)"* ]]
}

@test "create --dry-run shows the derived valet site name" {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    git branch feature/smoke
    local expected_site
    expected_site="$(shorten_name "$(basename "$TMP_ORIGIN")-feature/smoke" | tr '[:upper:]' '[:lower:]')"
    run "$SCRIPT" create feature/smoke --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] valet site: ${expected_site}.test"* ]]
}

@test "create --dry-run reads the valet TLD from valet config" {
    git branch feature/smoke
    export VALET_CONFIG="$(mktemp)"
    echo '{"tld": "develop"}' > "$VALET_CONFIG"
    run "$SCRIPT" create feature/smoke --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] valet site: "*".develop"* ]]
    rm -f "$VALET_CONFIG"
}

@test "create --dry-run warns when the valet server name exceeds the nginx bucket" {
    # Segments truncate to 4 chars, so crossing 64 takes many segments:
    # <repo>-feat-alph-brav-char-delt-echo-foxt-golf-hote-indi + .test + www.
    git branch feature/alpha/bravo/charlie/delta/echo/foxtrot/golf/hotel/india
    run "$SCRIPT" create feature/alpha/bravo/charlie/delta/echo/foxtrot/golf/hotel/india --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXCEEDS nginx's default server_names_hash_bucket_size"* ]]
    [[ "$output" == *"ALL valet sites"* ]]
}

@test "create --dir uses a custom directory name" {
    git branch feature/customdir
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    run "$SCRIPT" create feature/customdir --dir wt-customdir
    [ "$status" -eq 0 ]
    [ -d "$(dirname "$TMP_ORIGIN")/wt-customdir" ]
    git worktree list --porcelain | grep -qx "worktree $(dirname "$TMP_ORIGIN")/wt-customdir"
}

@test "create --dir rejects traversal and slashes" {
    git branch feature/customdir
    run "$SCRIPT" create feature/customdir --dir ../evil
    [ "$status" -ne 0 ]
    [[ "$output" == *"--dir must be a plain directory name"* ]]
    run "$SCRIPT" create feature/customdir --dir a/b
    [ "$status" -ne 0 ]
    [[ "$output" == *"--dir must be a plain directory name"* ]]
}

@test "destroy resolves a --dir worktree by branch name" {
    git branch feature/customdir
    cat > .worktree-bootstrap.yml <<'YAML'
database:
  driver: none
commands:
  install:
    - "true"
  build:
    - "true"
YAML
    run "$SCRIPT" create feature/customdir --dir wt-customdir
    [ "$status" -eq 0 ]
    run "$SCRIPT" destroy feature/customdir
    [ "$status" -eq 0 ]
    [ ! -d "$(dirname "$TMP_ORIGIN")/wt-customdir" ]
}

@test "destroy by branch name never resolves to the main repo" {
    # The current branch is checked out at the main repo; destroying it by
    # name must not touch the main checkout.
    local current
    current="$(git rev-parse --abbrev-ref HEAD)"
    run "$SCRIPT" destroy "$current" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would destroy"* ]]
    [[ "$output" != *"would destroy $TMP_ORIGIN and"* ]]
}

@test "create --dry-run shortens every name segment to 4 chars" {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    git branch feature/smoke
    local expected
    expected="$(dirname "$TMP_ORIGIN")/$(shorten_name "$(basename "$TMP_ORIGIN")-feature/smoke")"
    run "$SCRIPT" create feature/smoke --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would create worktree $expected "* ]]
    # Segments truncated: no segment longer than 4 chars in the dir basename.
    [[ "$(basename "$expected")" != *"feature"* ]]
}
