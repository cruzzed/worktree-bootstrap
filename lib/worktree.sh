#!/usr/bin/env bash
set -euo pipefail

# Resolve the main repo root. If override is provided, use it; otherwise derive from git common dir.
resolve_main_root() {
    local override="$1"
    if [[ -n "$override" ]]; then
        echo "$override"
        return 0
    fi
    local common
    common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || fatal "not inside a git repository"
    dirname "$common"
}

# Ensure cwd is not the main repo root.
require_not_main_root() {
    local main_root="$1"
    local worktree_root
    worktree_root="$(pwd)"
    if [[ "$worktree_root" == "$main_root" ]]; then
        fatal "you are running this from the main repo root. Create a worktree first."
    fi
}

# List worktree paths, one per line.
list_worktrees() {
    git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}'
}

# Create a worktree for a branch at a path.
create_worktree() {
    local branch="$1"
    local path="$2"
    git worktree add "$path" "$branch"
}

# Remove a worktree by path.
remove_worktree() {
    local path="$1"
    git worktree remove "$path" || rm -rf "$path"
}
