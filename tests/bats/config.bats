#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/config.sh"
    export TMP_CONFIG="$(mktemp).yml"
    cat > "$TMP_CONFIG" <<'EOF'
name: Test Project
copy_from_main:
  - .env
  - .claude/settings.local.json
database:
  driver: sqlite
  source_env_key: DB_DATABASE
ports:
  base:
    app: 8080
    db: 33060
commands:
  install:
    - npm ci
EOF
}

teardown() {
    rm -f "$TMP_CONFIG"
}

@test "load_config reads yaml via python3" {
    load_config "$TMP_CONFIG"
    [[ "$(get_config name)" == "Test Project" ]]
    [[ "$(get_config database.driver)" == "sqlite" ]]
}

@test "get_config returns empty for missing path" {
    load_config "$TMP_CONFIG"
    [[ -z "$(get_config does.not.exist)" ]]
}

@test "apply_defaults fills missing keys" {
    load_config "$TMP_CONFIG"
    apply_defaults
    [[ "$(get_config name)" == "Test Project" ]]
    [[ "$(get_config database.driver)" == "sqlite" ]]
    [[ "$(get_config ports.base.app)" == "8080" ]]
}

@test "apply_defaults applies when config is empty" {
    load_config "/nonexistent/config.yml"
    apply_defaults
    [[ "$(get_config name)" == "worktree-bootstrap project" ]]
    [[ "$(get_config database.driver)" == "mysql" ]]
    [[ "$(get_config copy_from_main[0])" == ".env" ]]
    [[ "$(get_config commands.install[0])" == "composer install" ]]
}

@test "render_template substitutes context keys" {
    local -A ctx=(
        [branch]=feature/foo-bar
        [branch_slug]=feature_foo_bar
        [site]=mysite
        [db_name]=explore_feature_foo_bar
        [worktree_root]=/tmp/wt
        [main_repo]=/tmp/main
        [ports.app]=8081
        [ports.db]=33061
    )
    local rendered
    rendered="$(render_template 'explore_{branch_slug}_{ports.app}' ctx)"
    [[ "$rendered" == "explore_feature_foo_bar_8081" ]]
    rendered="$(render_template '{db_name} {worktree_root} {main_repo} {site} {branch}' ctx)"
    [[ "$rendered" == "explore_feature_foo_bar /tmp/wt /tmp/main mysite feature/foo-bar" ]]
}

@test "render_env_refs substitutes existing env values" {
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    local env_file="$(mktemp)"
    printf 'DATABASE_URL=postgres://main\nQUOTED="some value"\n' > "$env_file"
    local rendered
    rendered="$(render_env_refs 'PARENT={env.DATABASE_URL} MISSING={env.NOPE} Q={env.QUOTED}' "$env_file")"
    [[ "$rendered" == "PARENT=postgres://main MISSING= Q=some value" ]]
    rm -f "$env_file"
}
