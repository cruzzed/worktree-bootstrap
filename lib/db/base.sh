#!/usr/bin/env bash
set -euo pipefail

# Dispatch a call to the configured DB driver.
db_call() {
    local driver="$1"
    local fn="$2"
    shift 2
    "db_${driver}_${fn}" "$@"
}

db_driver_available() {
    local driver="$1"
    db_call "$driver" available
}

db_exists() {
    local driver="$1"
    local target="$2"
    db_call "$driver" exists "$target"
}

db_create() {
    local driver="$1"
    local target="$2"
    db_call "$driver" create "$target"
}

db_drop() {
    local driver="$1"
    local target="$2"
    db_call "$driver" drop "$target"
}

db_clone() {
    local driver="$1"
    local source="$2"
    local target="$3"
    db_call "$driver" clone "$source" "$target"
}
