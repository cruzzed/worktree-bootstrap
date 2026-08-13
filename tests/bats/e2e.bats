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
        "${TMP_ORIGIN}-feature-destroy-hook"
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
    local app_port
    app_port="$(grep -oE '^APP_PORT=[0-9]+' .env | cut -d= -f2)"
    grep -qxF "CUSTOM_KEY=feature_env-${app_port}" .env
    grep -qxF "DB_DATABASE=${TMP_ORIGIN}-feature-env/explore_feature_env.sqlite" .env
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
