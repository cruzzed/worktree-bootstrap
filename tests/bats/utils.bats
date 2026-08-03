#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
}

@test "slugify converts branch names to safe slugs" {
    [[ "$(slugify 'feature/shopify-credit')" == "feature_shopify_credit" ]]
    [[ "$(slugify 'HOTFIX/ABC-123')" == "hotfix_abc_123" ]]
    [[ "$(slugify '---trim---')" == "trim" ]]
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
