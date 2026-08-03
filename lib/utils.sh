#!/usr/bin/env bash
set -euo pipefail

info() { echo "  $*"; }
warn() { echo "WARN: $*" >&2; }

fatal() {
    echo "FATAL: $*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local cmd="$1"
    command_exists "$cmd" || fatal "required command not found: $cmd"
}

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g' | sed -E 's/^_|_$//g' | cut -c1-60
}

is_git_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}
