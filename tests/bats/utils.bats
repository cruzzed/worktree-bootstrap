#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
}

@test "slugify converts branch names to safe slugs" {
    [[ "$(slugify 'feature/shopify-credit')" == "feature_shopify_credit" ]]
    [[ "$(slugify 'HOTFIX/ABC-123')" == "hotfix_abc_123" ]]
    [[ "$(slugify '---trim---')" == "trim" ]]
}

@test "shorten_name truncates every segment to 4 chars" {
    [[ "$(shorten_name 'MyRepo-feature/shopify-oauth-space-selector')" == "MyRe-feat-shop-oaut-spac-sele" ]]
    [[ "$(shorten_name 'repo-dev')" == "repo-dev" ]]
    [[ "$(shorten_name 'a/b_c.d--e')" == "a-b-c-d-e" ]]
    [[ "$(shorten_name '--lead/trail--')" == "lead-trai" ]]
    [[ "$(shorten_name 'exact')" == "exac" ]]
}

@test "command_exists finds existing commands" {
    command_exists bash
    ! command_exists this_command_definitely_does_not_exist_12345
}

@test "fatal prints to stderr and exits" {
    run bash -c 'source "$0/../../lib/utils.sh"; fatal "boom"' "$BATS_TEST_DIRNAME"
    [ "$status" -eq 1 ]
    [[ "$output" == *"boom"* ]]
}
