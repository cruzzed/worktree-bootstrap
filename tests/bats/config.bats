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

@test "render_template substitutes branch and slug" {
    local -A ports=([app]=8081 [db]=33061)
    local rendered
    rendered="$(render_template 'explore_{branch_slug}_{ports.app}' 'feature/foo-bar' 'feature_foo_bar' ports)"
    [[ "$rendered" == "explore_feature_foo_bar_8081" ]]
}
