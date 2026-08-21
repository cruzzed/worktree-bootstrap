#!/usr/bin/env bats

setup() {
    export TMP_ORIGIN="$(mktemp -d)"
    export SCRIPT="$BATS_TEST_DIRNAME/../../worktree-bootstrap.sh"
    cd "$TMP_ORIGIN"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -q -m "initial"
}

teardown() {
    # Remove the origin and any worktrees created next to it.
    rm -rf \
        "$TMP_ORIGIN" \
        "${TMP_ORIGIN}-feature-smoke" \
        "${TMP_ORIGIN}-feature-test" \
        "${TMP_ORIGIN}-feature-no-marker" \
        "${TMP_ORIGIN}-feature-dry-db" \
        "${TMP_ORIGIN}-feature-env" \
        "${TMP_ORIGIN}-feature-destroy-hook" \
        "${TMP_ORIGIN}-feature-plan" \
        "${TMP_ORIGIN}-feature-missing-hook" \
        "${TMP_ORIGIN}-feature-prune" \
        "${TMP_ORIGIN}-feature-delbr" \
        "${TMP_ORIGIN}-feature-dbcmd" \
        "${TMP_ORIGIN}-feature-nodb" \
        "${TMP_ORIGIN}-feature-bogus"
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
    grep -qxF "DB_DATABASE=${TMP_ORIGIN}-feature-env/explore_feature_env.sqlite" .env
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
    grep -qxF "DB_NAME=explore_feature_dbcmd" .env
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
