#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/worktree.sh"
    export TMP_ORIGIN="$(mktemp -d)"
    export TMP_WT="$(mktemp -d)"
    cd "$TMP_ORIGIN"
    git init -q
    git commit --allow-empty -q -m "initial"
    git branch feature/test
    git branch feature/new
}

teardown() {
    rm -rf "$TMP_ORIGIN" "$TMP_WT"
}

@test "resolve_main_root auto-detects main repo from worktree" {
    cd "$TMP_ORIGIN"
    git worktree add -q "$TMP_WT/wt" feature/test
    cd "$TMP_WT/wt"
    local main
    main="$(resolve_main_root "")"
    [[ "$main" == "$TMP_ORIGIN" ]]
}

@test "create_worktree creates a worktree directory" {
    cd "$TMP_ORIGIN"
    create_worktree "feature/new" "$TMP_WT/new"
    [[ -e "$TMP_WT/new/.git" ]]
}
