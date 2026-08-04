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
        "${TMP_ORIGIN}-feature-dry-db"
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
