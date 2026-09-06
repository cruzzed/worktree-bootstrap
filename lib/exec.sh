#!/usr/bin/env bash
set -euo pipefail

# Run a command inside a worktree with its execution context: the worktree
# directory as cwd, its .env exported, and its .venv/bin, vendor/bin, and
# node_modules/.bin prepended to PATH. The command resolves in this order:
#
#   1. a preset script `.wtbs/<name>` (worktree checkout first, then the main
#      repo) — run with bash, extra args as positional parameters, and the
#      template context exported as WTBS_* env vars (no template rendering,
#      so scripts may contain literal { braces);
#   2. an alias from the project config (`aliases.<name>`) — rendered with the
#      template context ({ports.serve}, {db_name}, {site}, ...), extra args
#      appended;
#   3. a raw command run verbatim (still template-rendered).

# Internal: echo the path of the preset script for a name, if one exists.
_find_preset() {
    local worktree_path="$1" main_root="$2" name="$3"
    if [[ -f "$worktree_path/.wtbs/$name" ]]; then
        echo "$worktree_path/.wtbs/$name"
    elif [[ -f "$main_root/.wtbs/$name" ]]; then
        echo "$main_root/.wtbs/$name"
    fi
}

# Internal: export the template context as WTBS_* env vars for preset scripts.
_export_context_vars() {
    local -n ctx_ref="$1"
    export WTBS_BRANCH="${ctx_ref[branch]}"
    export WTBS_BRANCH_SLUG="${ctx_ref[branch_slug]}"
    export WTBS_SITE="${ctx_ref[site]}"
    export WTBS_DB_NAME="${ctx_ref[db_name]}"
    export WTBS_WORKTREE_ROOT="${ctx_ref[worktree_root]}"
    export WTBS_MAIN_REPO="${ctx_ref[main_repo]}"
    local key pname
    for key in "${!ctx_ref[@]}"; do
        [[ "$key" == ports.* ]] || continue
        pname="WTBS_PORT_${key#ports.}"
        export "${pname^^}=${ctx_ref[$key]}"
    done
}

# Internal: list available presets and aliases for a worktree.
_list_commands() {
    local ctx_name="$1" worktree_path="$2" main_root="$3"
    local -n list_ctx="$ctx_name"

    local -A presets=()
    local dir f
    for dir in "$main_root/.wtbs" "$worktree_path/.wtbs"; do
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*; do
            [[ -f "$f" ]] || continue
            # Worktree presets shadow main-repo presets of the same name.
            presets["$(basename "$f")"]="$f"
        done
    done
    if [[ ${#presets[@]} -gt 0 ]]; then
        echo "presets (.wtbs/):"
        local name
        while IFS= read -r name; do
            printf '  %-16s %s\n' "$name" "${presets[$name]}"
        done < <(printf '%s\n' "${!presets[@]}" | sort)
    fi

    local -a keys=()
    local k
    while IFS= read -r k; do
        keys+=("$k")
    done < <(printf '%s\n' "${!CONFIG[@]}" | grep -E '^aliases\.' | sort || true)
    if [[ ${#keys[@]} -gt 0 ]]; then
        echo "aliases (.worktree-bootstrap.yml):"
        for k in "${keys[@]}"; do
            printf '  %-16s %s\n' "${k#aliases.}" "$(render_template "${CONFIG[$k]}" list_ctx)"
        done
    fi

    if [[ ${#presets[@]} -eq 0 && ${#keys[@]} -eq 0 ]]; then
        echo "no presets (.wtbs/) or aliases (config) defined for this project"
    fi
}

cmd_exec() {
    local target="$1"
    shift

    local main_root worktree_path=""
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"

    if _is_worktree_path "$target"; then
        worktree_path="$(cd "$target" && pwd)"
    else
        worktree_path="$(_worktree_path_for_branch "$target")"
        if [[ -z "$worktree_path" ]]; then
            local candidate
            candidate="$(dirname "$main_root")/$(basename "$main_root")-${target//\//-}"
            [[ -d "$candidate" ]] && worktree_path="$candidate"
        fi
    fi
    [[ -n "$worktree_path" && -d "$worktree_path" ]] || fatal "no worktree found for: $target"

    load_project_config "$main_root"

    local branch branch_slug site env_file offset="" db_name=""
    branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="unknown"
    branch_slug="$(slugify "$branch")"
    site="$(basename "$worktree_path" | tr '[:upper:]' '[:lower:]')"
    env_file="$worktree_path/.env"
    if [[ -f "$env_file" ]]; then
        offset="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:offset:([0-9]+):.*/\1/' || true)"
        db_name="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:db:(.*)$/\1/' || true)"
    fi
    if [[ -z "$db_name" ]]; then
        db_name="$(get_config database.name_prefix)${branch_slug}"
    fi

    local -A base_ports ports
    base_ports[app]="$(get_config ports.base.app)"
    base_ports[db]="$(get_config ports.base.db)"
    base_ports[vite]="$(get_config ports.base.vite)"
    base_ports[serve]="$(get_config ports.base.serve)"
    base_ports[redis]="$(get_config ports.base.redis)"
    base_ports[mailhog]="$(get_config ports.base.mailhog)"
    compute_ports "${offset:-0}" base_ports ports

    local -A ctx
    build_context ctx "$branch" "$branch_slug" "$site" "$db_name" "$worktree_path" "$main_root" ports

    # No command: list the presets and aliases available for this worktree.
    if [[ $# -eq 0 ]]; then
        echo "worktree: $worktree_path"
        _list_commands ctx "$worktree_path" "$main_root"
        return 0
    fi

    local preset
    preset="$(_find_preset "$worktree_path" "$main_root" "$1")"

    if [[ -n "$preset" ]]; then
        shift
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[dry-run] worktree: $worktree_path"
            echo "[dry-run] would export: $env_file"
            echo "[dry-run] would run preset: bash $preset $*"
            return 0
        fi
        local status=0
        (
            cd "$worktree_path"
            local bindir
            for bindir in .venv/bin vendor/bin node_modules/.bin; do
                [[ -d "$bindir" ]] && PATH="$worktree_path/$bindir:$PATH"
            done
            export PATH
            export_env_file "$env_file"
            _export_context_vars ctx
            # WARNING: presets are project files executed as-is. Only run this
            # against repositories whose .wtbs/ scripts you trust.
            # Worktree checkouts may carry CRLF line endings (core.autocrlf),
            # which corrupts bash syntax; strip trailing CR before running.
            bash <(sed 's/\r$//' "$preset") "$@"
        ) || status=$?
        return "$status"
    fi

    # Alias match (extra args appended) or raw command pass-through.
    local cmd
    local alias_val="${CONFIG["aliases.$1"]:-}"
    if [[ -n "$alias_val" ]]; then
        shift
        cmd="$alias_val"
        [[ $# -gt 0 ]] && cmd="$cmd $*"
    else
        cmd="$*"
    fi
    cmd="$(render_template "$cmd" ctx)"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] worktree: $worktree_path"
        echo "[dry-run] would export: $env_file"
        echo "[dry-run] would run: $cmd"
        return 0
    fi

    local status=0
    (
        cd "$worktree_path"
        local bindir
        for bindir in .venv/bin vendor/bin node_modules/.bin; do
            [[ -d "$bindir" ]] && PATH="$worktree_path/$bindir:$PATH"
        done
        export PATH
        export_env_file "$env_file"
        # WARNING: alias text comes from the project config and is executed
        # as-is. Only run this against repositories whose config you trust.
        bash -c "$cmd"
    ) || status=$?
    return "$status"
}
