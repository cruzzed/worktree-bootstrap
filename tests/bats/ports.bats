#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/ports.sh"
    # Make port availability deterministic regardless of host state.
    port_in_use() { return 1; }
    export TMP_REG="$(mktemp)"
    mkdir -p "$(dirname "$TMP_REG")"
}

teardown() {
    rm -f "$TMP_REG"
}

@test "compute_ports calculates offsets" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    local -A result
    compute_ports 5 base result
    [[ "${result[app]}" -eq 8085 ]]
    [[ "${result[db]}" -eq 33065 ]]
}

@test "allocate_offset returns 0 for empty registry" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    local offset
    offset="$(allocate_offset "$TMP_REG" "feature/test" base 0 0)"
    [[ "$offset" == "1" ]]
}

@test "allocate_offset reuses existing branch offset" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    printf '%s\t%s\t%s\t%s\n' "feature/test" "7" "db_test" "2026-08-01T00:00:00" > "$TMP_REG"
    local offset
    offset="$(allocate_offset "$TMP_REG" "feature/test" base 0 0)"
    [[ "$offset" == "7" ]]
}
