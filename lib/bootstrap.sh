#!/usr/bin/env bash
set -euo pipefail

# Source all modules.
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/env.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/ports.sh"
source "${LIB_DIR}/worktree.sh"
source "${LIB_DIR}/db/base.sh"
source "${LIB_DIR}/db/mysql.sh"
source "${LIB_DIR}/db/sqlite.sh"
source "${LIB_DIR}/db/postgres.sh"

# Globals set by parse_args.
DRY_RUN=0
FORCE_CLONE=0
CHECK_REDIS=0
CHECK_MAILHOG=0
MAIN_ROOT_OVERRIDE=""
CONFIG_PATH_OVERRIDE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --force-clone) FORCE_CLONE=1 ;;
            --check-redis) CHECK_REDIS=1 ;;
            --check-mailhog) CHECK_MAILHOG=1 ;;
            --main-repo) shift; MAIN_ROOT_OVERRIDE="$1" ;;
            --config) shift; CONFIG_PATH_OVERRIDE="$1" ;;
            *) fatal "unknown option: $1" ;;
        esac
        shift
    done
}

load_project_config() {
    local main_root="$1"
    local config_path="${CONFIG_PATH_OVERRIDE:-$main_root/.worktree-bootstrap.yml}"
    load_config "$config_path"
    apply_defaults
}

# Export DB env keys into the generic names drivers expect.
export_db_env() {
    local env_file="$1"
    local source_key host_key port_key user_key pass_key
    source_key="$(get_config database.source_env_key)"
    host_key="$(get_config database.host_env_key)"
    port_key="$(get_config database.port_env_key)"
    user_key="$(get_config database.user_env_key)"
    pass_key="$(get_config database.pass_env_key)"

    DB_DATABASE="$(env_value "$env_file" "$source_key")"
    DB_HOST="$(env_value "$env_file" "$host_key")"
    DB_PORT="$(env_value "$env_file" "$port_key")"
    DB_USERNAME="$(env_value "$env_file" "$user_key")"
    DB_PASSWORD="$(env_value "$env_file" "$pass_key")"

    export DB_DATABASE DB_HOST DB_PORT DB_USERNAME DB_PASSWORD
}

run_commands() {
    local step="$1"
    local branch="${2:-}" branch_slug="${3:-}" site="${4:-}" ports_name="${5:-}"
    local -a cmds=()
    local i=0
    while true; do
        local key="commands.${step}[${i}]"
        local val="${CONFIG[$key]:-}"
        [[ -z "$val" ]] && break
        cmds+=("$val")
        i=$((i + 1))
    done

    local cmd rendered_cmd
    for cmd in "${cmds[@]}"; do
        rendered_cmd="$cmd"
        if [[ -n "$ports_name" ]]; then
            rendered_cmd="$(render_template "$cmd" "$branch" "$branch_slug" "$ports_name" "$site")"
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[dry-run] would run: $rendered_cmd"
        else
            info "running: $rendered_cmd"
            # WARNING: commands come from the project config and are executed as-is.
            # Only run this tool against repositories whose bootstrap commands you trust.
            eval "$rendered_cmd" || fatal "command failed: $rendered_cmd"
        fi
    done
}

cmd_bootstrap() {
    local main_root worktree_root branch branch_slug env_file driver db_name
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"
    worktree_root="$(pwd)"

    require_not_main_root "$main_root"

    load_project_config "$main_root"

    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    branch_slug="$(slugify "$branch")"

    env_file="$worktree_root/.env"

    echo "── worktree-bootstrap preflight ──────────────────────────"
    echo "  worktree : $worktree_root"
    echo "  main repo: $main_root"
    echo "  branch   : $branch"

    # Copy files.
    if [[ $DRY_RUN -eq 0 ]]; then
        local -a files=()
        local i=0
        while true; do
            local key="copy_from_main[${i}]"
            local val="${CONFIG[$key]:-}"
            [[ -z "$val" ]] && break
            files+=("$val")
            i=$((i + 1))
        done
        copy_files "$main_root" "$worktree_root" "${files[@]}"
        info "copied config files"
    else
        echo "[dry-run] would copy config files"
    fi

    # Load DB env.
    export_db_env "$env_file"
    local name_prefix
    name_prefix="$(get_config database.name_prefix)"
    db_name="${name_prefix}${branch_slug}"
    echo "  target db: $db_name"

    # Allocate ports.
    local -A base_ports
    base_ports[app]="$(get_config ports.base.app)"
    base_ports[db]="$(get_config ports.base.db)"
    base_ports[vite]="$(get_config ports.base.vite)"
    base_ports[serve]="$(get_config ports.base.serve)"
    base_ports[redis]="$(get_config ports.base.redis)"
    base_ports[mailhog]="$(get_config ports.base.mailhog)"

    local registry_file="$main_root/.worktree-bootstrap/ports.tsv"
    local offset
    offset="$(allocate_offset "$registry_file" "$branch" base_ports "$CHECK_REDIS" "$CHECK_MAILHOG")"

    local -A ports
    compute_ports "$offset" base_ports ports

    # Database clone.
    driver="$(get_config database.driver)"
    local db_source="$DB_DATABASE"
    local db_target="$db_name"
    if [[ "$driver" == "sqlite" ]]; then
        local sqlite_source
        sqlite_source="$(get_config database.sqlite_source_path)"
        [[ -z "$sqlite_source" ]] && sqlite_source="$DB_DATABASE"
        db_source="$main_root/$sqlite_source"
        db_target="$worktree_root/${db_name}.sqlite"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] would create/clone database $db_target"
    elif db_driver_available "$driver"; then
        if db_exists "$driver" "$db_target"; then
            if [[ $FORCE_CLONE -eq 1 ]]; then
                db_drop "$driver" "$db_target"
            else
                warn "database $db_target already exists; skipping clone"
            fi
        fi

        if [[ $FORCE_CLONE -eq 1 ]] || ! db_exists "$driver" "$db_target"; then
            db_create "$driver" "$db_target"
            db_clone "$driver" "$db_source" "$db_target"
            info "cloned database $db_source -> $db_target"
        fi
    else
        warn "$driver driver not available; skipping database clone"
    fi

    # Site name: lowercased worktree directory basename (matches the Valet site).
    local site
    site="$(basename "$worktree_root" | tr '[:upper:]' '[:lower:]')"

    # Update env.
    if [[ $DRY_RUN -eq 0 ]]; then
        # Apply every env_updates entry from the config, rendered through
        # {branch}/{branch_slug}/{site}/{ports.*} templates.
        local -A seen=()
        local cfg_key env_key rendered
        for cfg_key in "${!CONFIG[@]}"; do
            [[ "$cfg_key" == env_updates.* ]] || continue
            env_key="${cfg_key#env_updates.}"
            rendered="$(render_template "${CONFIG[$cfg_key]}" "$branch" "$branch_slug" ports "$site")"
            update_env_key "$env_file" "$env_key" "$rendered"
            seen[$env_key]=1
        done

        # Built-in defaults for keys not set via env_updates.
        if [[ -z "${seen[DB_DATABASE]:-}" ]]; then
            if [[ "$driver" == "sqlite" ]]; then
                update_env_key "$env_file" "DB_DATABASE" "$db_target"
            else
                update_env_key "$env_file" "DB_DATABASE" "$db_name"
            fi
        fi
        [[ -n "${seen[APP_PORT]:-}" ]] || update_env_key "$env_file" "APP_PORT" "${ports[app]}"
        [[ -n "${seen[FORWARD_DB_PORT]:-}" ]] || update_env_key "$env_file" "FORWARD_DB_PORT" "${ports[db]}"
        [[ -n "${seen[VITE_PORT]:-}" ]] || update_env_key "$env_file" "VITE_PORT" "${ports[vite]}"
        write_marker "$env_file" "$branch" "$offset" "$db_name"
        register_offset "$registry_file" "$branch" "$offset" "$db_name"
    else
        echo "[dry-run] would update .env and register offset $offset"
    fi

    # Install and build.
    run_commands install "$branch" "$branch_slug" "$site" ports
    run_commands build "$branch" "$branch_slug" "$site" ports

    # Report.
    echo ""
    echo "── worktree-bootstrap report ─────────────────────────────"
    echo "  branch .............. $branch"
    echo "  database ............ $db_name"
    echo "  APP_PORT ............ ${ports[app]}"
    echo "  FORWARD_DB_PORT ..... ${ports[db]}"
    echo "  VITE_PORT ........... ${ports[vite]}"
    echo "  SERVE_PORT .......... ${ports[serve]}"
    echo "──────────────────────────────────────────────────────────"
}

cmd_create() {
    local branch="$1"
    local main_root worktree_path
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"
    worktree_path="$(dirname "$main_root")/$(basename "$main_root")-${branch//\//-}"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] would create worktree $worktree_path for branch $branch"
        return 0
    fi

    create_worktree "$branch" "$worktree_path"

    (
        cd "$worktree_path"
        cmd_bootstrap
    )
}

cmd_destroy() {
    local target="$1"
    local main_root worktree_path branch env_file offset db_name driver
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"

    # Resolve path from branch name if needed.
    if [[ -d "$target" ]]; then
        worktree_path="$target"
    else
        worktree_path="$(dirname "$main_root")/$(basename "$main_root")-${target//\//-}"
    fi

    branch="$(cd "$worktree_path" && git rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="unknown"
    env_file="$worktree_path/.env"

    load_project_config "$main_root"
    driver="$(get_config database.driver)"

    if [[ -f "$env_file" ]]; then
        export_db_env "$env_file"
        offset="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:offset:([0-9]+):.*/\1/' || true)"
        db_name="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:db:(.*)$/\1/' || true)"
    fi

    # Optional destroy hook commands (e.g. valet unsecure), rendered with the
    # same template context as bootstrap. Hook failures abort teardown, so
    # best-effort commands should end with `|| true`.
    local site branch_slug
    site="$(basename "$worktree_path" | tr '[:upper:]' '[:lower:]')"
    branch_slug="$(slugify "$branch")"
    local -A base_ports ports
    base_ports[app]="$(get_config ports.base.app)"
    base_ports[db]="$(get_config ports.base.db)"
    base_ports[vite]="$(get_config ports.base.vite)"
    base_ports[serve]="$(get_config ports.base.serve)"
    base_ports[redis]="$(get_config ports.base.redis)"
    base_ports[mailhog]="$(get_config ports.base.mailhog)"
    compute_ports "${offset:-0}" base_ports ports
    run_commands destroy "$branch" "$branch_slug" "$site" ports

    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ -n "${db_name:-}" ]] && db_driver_available "$driver"; then
            db_drop "$driver" "$db_name" || warn "failed to drop database $db_name"
        fi
        remove_worktree "$worktree_path"
        if [[ -n "${offset:-}" ]]; then
            local registry_file="$main_root/.worktree-bootstrap/ports.tsv"
            if [[ -f "$registry_file" ]]; then
                local escaped_branch tmp
                escaped_branch="$(regex_escape "$branch")"
                tmp="$(mktemp)"
                grep -vE "^${escaped_branch}"$'\t' "$registry_file" > "$tmp" || true
                mv "$tmp" "$registry_file"
            fi
        fi
    else
        echo "[dry-run] would destroy $worktree_path and drop ${db_name:-<unknown>}"
    fi
}
