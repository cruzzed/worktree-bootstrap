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

# Shorten a name by truncating each separator-delimited segment to 4 chars.
# Any run of non-alphanumeric characters counts as a separator; segments are
# re-joined with '-'. Keeps worktree directory names (and the valet server
# names derived from them) short even for long branch names:
#   MyRepo-feature/shopify-oauth-space-selector -> MyRe-feat-shop-oaut-spac-sele
shorten_name() {
    local name="$1"
    name="$(echo "$name" | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')"
    awk -F- '{
        out = ""
        for (i = 1; i <= NF; i++) {
            if ($i != "") out = out (out == "" ? "" : "-") substr($i, 1, 4)
        }
        print out
    }' <<< "$name"
}

is_git_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}
