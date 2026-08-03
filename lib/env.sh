#!/usr/bin/env bash
set -euo pipefail

# Read a value from a KEY=VALUE .env file. Handles optional quotes.
env_value() {
    local file="$1"
    local key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | sed -E "s/^${key}=//" | sed -E "s/^['\"](.*)['\"]$/\1/"
}

# Copy an array of files from source_dir to dest_dir. Missing files are skipped silently.
copy_files() {
    local source_dir="$1"
    local dest_dir="$2"
    shift 2
    local files=("$@")
    local file rel_dir

    for file in "${files[@]}"; do
        [[ -f "$source_dir/$file" ]] || continue
        rel_dir="$(dirname "$file")"
        mkdir -p "$dest_dir/$rel_dir"
        cp "$source_dir/$file" "$dest_dir/$file"
    done
}

# Update or append a key in an .env file.
update_env_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i -E "s/^${key}=.*/${key}=${value}/" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# Remove the WORKTREE_BOOTSTRAP idempotency marker from an .env file.
remove_marker() {
    local file="$1"
    sed -i '/^# WORKTREE_BOOTSTRAP=/d' "$file"
}

# Append a fresh marker line.
write_marker() {
    local file="$1"
    local branch="$2"
    local offset="$3"
    local db_name="$4"
    remove_marker "$file"
    echo "# WORKTREE_BOOTSTRAP=branch:${branch}:offset:${offset}:db:${db_name}" >> "$file"
}
