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

# Default worktree path for a branch: a sibling directory of the main repo
# named <repo>-<branch> with every separator-delimited segment truncated to
# 4 chars, so long branch names stay short enough for valet/nginx.
default_worktree_path() {
    local main_root="$1" branch="$2"
    echo "$(dirname "$main_root")/$(shorten_name "$(basename "$main_root")-$branch")"
}

# Create a worktree for a branch at a path. If the branch does not exist yet,
# create it from the optional base ref (defaults to HEAD).
create_worktree() {
    local branch="$1"
    local path="$2"
    local base="${3:-}"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add "$path" "$branch"
    else
        info "branch '$branch' does not exist; creating from ${base:-HEAD}"
        if [[ -n "$base" ]]; then
            git worktree add -b "$branch" "$path" "$base"
        else
            git worktree add -b "$branch" "$path"
        fi
    fi
}

# Internal: return 0 if the directory is a registered worktree path.
_is_worktree_path() {
    local path="$1"
    [[ -d "$path" ]] || return 1
    local abs_path
    abs_path="$(cd "$path" && pwd)"
    [[ -e "$abs_path/.git" ]] || return 1
    git worktree list --porcelain 2>/dev/null | grep -qx "worktree $abs_path"
}

# Internal: resolve a branch name to its registered worktree path.
_worktree_path_for_branch() {
    local branch="$1"
    git worktree list --porcelain 2>/dev/null | awk -v b="$branch" '
        /^worktree / { path=$2 }
        /^branch / {
            ref=$2
            sub(/^refs\/heads\//, "", ref)
            if (ref == b) { print path; exit }
        }
    '
}

# Derive the valet server name for a worktree directory: the lowercased
# basename plus the valet TLD. The TLD is read from valet's config.json when
# present (VALET_CONFIG overrides the path, mainly for tests); otherwise
# "test" is assumed.
valet_site_name() {
    local worktree_path="$1"
    local site tld="test" config detected
    site="$(basename "$worktree_path" | tr '[:upper:]' '[:lower:]')"
    config="${VALET_CONFIG:-$HOME/.config/valet/config.json}"
    if [[ -f "$config" ]]; then
        detected="$(grep -oE '"tld"[[:space:]]*:[[:space:]]*"[^"]+"' "$config" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')"
        [[ -n "$detected" ]] && tld="$detected"
    fi
    echo "$site.$tld"
}

# Warn when the valet server name derived from a worktree directory would
# approach nginx's default server_names_hash_bucket_size (64): valet writes
# <site>.<tld> plus www. and *. variants, and an over-long server name makes
# the nginx config test fail — nginx then refuses to start for EVERY valet
# site on the machine, with no hint that a directory name caused it.
warn_long_site_name() {
    local worktree_path="$1"
    local fqdn longest
    fqdn="$(valet_site_name "$worktree_path")"
    longest=$(( 4 + ${#fqdn} ))  # "www." prefix variant
    if [[ $longest -gt 64 ]]; then
        warn "valet server name 'www.$fqdn' ($longest chars) EXCEEDS nginx's default server_names_hash_bucket_size (64)"
        warn "securing this site will make nginx fail to start for ALL valet sites on this machine"
        warn "use a shorter branch name or --dir <name>, or raise server_names_hash_bucket_size in nginx.conf"
    elif [[ $longest -gt 56 ]]; then
        warn "valet server name 'www.$fqdn' ($longest chars) is close to nginx's default server_names_hash_bucket_size (64)"
        warn "consider a shorter branch name or --dir <name>"
    fi
}

# Internal: safely remove a leftover worktree directory after git worktree remove fails.
_safe_remove_path() {
    local path="$1"
    if _is_worktree_path "$path" || git worktree list --porcelain 2>/dev/null | grep -qx "worktree $path"; then
        rm -rf "$path"
    else
        fatal "refusing unsafe removal of non-worktree path: $path"
    fi
}

# Remove a worktree by path.
remove_worktree() {
    local path="$1"
    local dry_run="${2:-}"
    if [[ "$dry_run" == "1" || "$dry_run" == "true" ]]; then
        echo "[dry-run] would remove worktree: $path"
        return 0
    fi
    git worktree remove "$path" 2>/dev/null || _safe_remove_path "$path"
}

# Remove a worktree by branch name or path.
destroy_worktree() {
    local branch_or_path="$1"
    local dry_run="${2:-}"
    local path=""
    if _is_worktree_path "$branch_or_path"; then
        path="$branch_or_path"
    else
        path="$(_worktree_path_for_branch "$branch_or_path")"
    fi
    [[ -n "$path" ]] || fatal "no worktree found for: $branch_or_path"
    remove_worktree "$path" "$dry_run"
}
