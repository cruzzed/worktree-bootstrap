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

# Globals set by argument parsing.
DRY_RUN=0
FORCE_CLONE=0
CHECK_REDIS=0
CHECK_MAILHOG=0
MAIN_ROOT_OVERRIDE=""
CONFIG_PATH_OVERRIDE=""
BASE_REF=""
DELETE_BRANCH=0
WORKTREE_ROOT_OVERRIDE=""
BRANCH_OVERRIDE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --force-clone) FORCE_CLONE=1 ;;
            --check-redis) CHECK_REDIS=1 ;;
            --check-mailhog) CHECK_MAILHOG=1 ;;
            --delete-branch) DELETE_BRANCH=1 ;;
            --main-repo) shift; MAIN_ROOT_OVERRIDE="$1" ;;
            --config) shift; CONFIG_PATH_OVERRIDE="$1" ;;
            --base) shift; BASE_REF="$1" ;;
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

# Collect commands.<step>[i] entries into the named array.
config_commands() {
    local step="$1"
    local -n out_ref="$2"
    out_ref=()
    local i=0 val
    while true; do
        val="${CONFIG["commands.${step}[${i}]"]:-}"
        [[ -z "$val" ]] && break
        out_ref+=("$val")
        i=$((i + 1))
    done
}

# Build the template context associative array. Keys: branch, branch_slug,
# site, db_name, worktree_root, main_repo, and ports.<name>.
build_context() {
    local -n ctx_out="$1"
    local branch="$2" branch_slug="$3" site="$4" db_name="$5"
    local worktree_root="$6" main_root="$7"
    local -n ctx_ports="$8"

    ctx_out[branch]="$branch"
    ctx_out[branch_slug]="$branch_slug"
    ctx_out[site]="$site"
    ctx_out[db_name]="$db_name"
    ctx_out[worktree_root]="$worktree_root"
    ctx_out[main_repo]="$main_root"
    local k
    for k in "${!ctx_ports[@]}"; do
        ctx_out["ports.$k"]="${ctx_ports[$k]}"
    done
}

run_commands() {
    local step="$1" ctx_name="$2"
    local -a cmds=()
    config_commands "$step" cmds

    local cmd rendered_cmd
    for cmd in ${cmds[@]+"${cmds[@]}"}; do
        rendered_cmd="$(render_template "$cmd" "$ctx_name")"
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

# Fail fast when hook scripts referenced in commands.* or database.create/drop
# are missing from the checkout. Only tokens that look like paths (contain a
# "/") are checked; plain command names are assumed to be on PATH.
# Mode "fail" aborts with a clear message; mode "warn" only prints a warning
# (used by create --dry-run, where the worktree does not exist yet).
preflight_hook_scripts() {
    local ctx_name="$1" check_root="$2" mode="$3"

    local -a entries=()
    local step
    for step in install build serve destroy; do
        local -a step_cmds=()
        config_commands "$step" step_cmds
        entries+=(${step_cmds[@]+"${step_cmds[@]}"})
    done
    local db_cmd
    for db_cmd in "$(get_config database.create)" "$(get_config database.drop)"; do
        [[ -n "$db_cmd" ]] && entries+=("$db_cmd")
    done

    local -a missing=()
    local entry rendered token path
    for entry in ${entries[@]+"${entries[@]}"}; do
        [[ -z "$entry" ]] && continue
        rendered="$(render_template "$entry" "$ctx_name")"
        token="${rendered%%[[:space:]]*}"
        [[ "$token" == */* ]] || continue
        if [[ "$token" == /* ]]; then
            path="$token"
        else
            path="$check_root/$token"
        fi
        [[ -e "$path" ]] || missing+=("$token")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ "$mode" == "warn" ]]; then
            warn "hook scripts not found in $check_root: ${missing[*]}"
        else
            printf 'FATAL: hook script not found in worktree: %s\n' "${missing[@]}" >&2
            fatal "commit the missing scripts to the branch, or fix commands.* in .worktree-bootstrap.yml"
        fi
    fi
}

# Determine which ports are actually referenced (via {ports.<name>}) in
# env_updates, commands.*, or database.create/drop. Sets used_ports_out keys.
collect_used_ports() {
    local -n used_out="$1"
    used_out=()
    local cfg_key val
    for cfg_key in "${!CONFIG[@]}"; do
        case "$cfg_key" in
            env_updates.*|commands.*|database.create|database.drop) ;;
            *) continue ;;
        esac
        val="${CONFIG[$cfg_key]}"
        while [[ "$val" =~ \{ports\.([a-z]+)\} ]]; do
            used_out[${BASH_REMATCH[1]}]=1
            val="${val#*"${BASH_REMATCH[0]}"}"
        done
    done
}

cmd_bootstrap() {
    local main_root worktree_root branch branch_slug env_file driver db_name db_action
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"
    if [[ -n "$WORKTREE_ROOT_OVERRIDE" ]]; then
        worktree_root="$WORKTREE_ROOT_OVERRIDE"
    else
        worktree_root="$(pwd)"
        require_not_main_root "$main_root"
    fi

    load_project_config "$main_root"

    branch="${BRANCH_OVERRIDE:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
    branch_slug="$(slugify "$branch")"

    env_file="$worktree_root/.env"
    # In create --dry-run the worktree (and its .env) does not exist yet;
    # resolve {env.KEY} references against the main repo's .env, which is
    # what copy_from_main would seed the worktree with.
    local env_refs_file="$env_file"
    if [[ -n "$WORKTREE_ROOT_OVERRIDE" && ! -f "$env_file" ]]; then
        env_refs_file="$main_root/.env"
    fi

    echo "── worktree-bootstrap preflight ──────────────────────────"
    echo "  worktree : $worktree_root"
    echo "  main repo: $main_root"
    echo "  branch   : $branch"

    # Load DB env.
    export_db_env "$env_file"
    local name_prefix
    name_prefix="$(get_config database.name_prefix)"
    db_name="${name_prefix}${branch_slug}"
    driver="$(get_config database.driver)"
    echo "  driver   : $driver"
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
    offset="$(allocate_offset "$registry_file" "$branch" base_ports "$CHECK_REDIS" "$CHECK_MAILHOG" "$DRY_RUN")"

    local -A ports
    compute_ports "$offset" base_ports ports

    # Template context for hooks, env_updates, and database commands.
    local site
    site="$(basename "$worktree_root" | tr '[:upper:]' '[:lower:]')"
    local -A ctx
    build_context ctx "$branch" "$branch_slug" "$site" "$db_name" "$worktree_root" "$main_root" ports

    # Fail fast on missing hook scripts before changing anything. When the
    # worktree does not exist yet (create --dry-run), warn against the main
    # repo instead.
    if [[ -n "$WORKTREE_ROOT_OVERRIDE" ]]; then
        preflight_hook_scripts ctx "$main_root" warn
    else
        preflight_hook_scripts ctx "$worktree_root" fail
    fi

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
        copy_files "$main_root" "$worktree_root" ${files[@]+"${files[@]}"}
        info "copied config files"
    else
        echo "[dry-run] would copy config files"
    fi

    # Database step. driver "none" disables it; database.create replaces the
    # built-in driver dispatch with a rendered command.
    local db_source="$DB_DATABASE"
    local db_target="$db_name"
    if [[ "$driver" == "sqlite" ]]; then
        local sqlite_source
        sqlite_source="$(get_config database.sqlite_source_path)"
        [[ -z "$sqlite_source" ]] && sqlite_source="$DB_DATABASE"
        db_source="$main_root/$sqlite_source"
        db_target="$worktree_root/${db_name}.sqlite"
    fi

    local db_create_cmd
    db_create_cmd="$(get_config database.create)"
    db_action=""
    if [[ -n "$db_create_cmd" ]]; then
        local rendered_create
        rendered_create="$(render_template "$db_create_cmd" ctx)"
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[dry-run] would run database.create: $rendered_create"
            db_action="would run database.create"
        else
            info "running: $rendered_create"
            # Same trust warning as run_commands applies here.
            eval "$rendered_create" || fatal "command failed: $rendered_create"
            db_action="created via database.create"
        fi
    elif [[ "$driver" == "none" ]]; then
        db_action="skipped (disabled)"
    elif [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] would create/clone database $db_target"
        db_action="would clone $db_source -> $db_target"
    elif db_driver_available "$driver"; then
        if db_exists "$driver" "$db_target"; then
            if [[ $FORCE_CLONE -eq 1 ]]; then
                db_drop "$driver" "$db_target"
            else
                warn "database $db_target already exists; skipping clone"
                db_action="already exists (skipped clone)"
            fi
        fi

        if [[ $FORCE_CLONE -eq 1 ]] || ! db_exists "$driver" "$db_target"; then
            db_create "$driver" "$db_target"
            db_clone "$driver" "$db_source" "$db_target"
            info "cloned database $db_source -> $db_target"
            db_action="cloned $db_source -> $db_target"
        fi
    else
        warn "$driver driver not available; skipping database clone"
        db_action="skipped ($driver driver not available)"
    fi

    # Update env.
    if [[ $DRY_RUN -eq 0 ]]; then
        # Apply every env_updates entry from the config, rendered through the
        # full template context plus {env.KEY} references to existing values.
        local -A seen=()
        local cfg_key env_key rendered
        for cfg_key in "${!CONFIG[@]}"; do
            [[ "$cfg_key" == env_updates.* ]] || continue
            env_key="${cfg_key#env_updates.}"
            rendered="$(render_env_refs "${CONFIG[$cfg_key]}" "$env_refs_file")"
            rendered="$(render_template "$rendered" ctx)"
            update_env_key "$env_file" "$env_key" "$rendered"
            seen[$env_key]=1
        done

        # Built-in DB name write for real drivers (not "none", not
        # command-based provisioning, which owns its env itself).
        if [[ -z "${seen[DB_DATABASE]:-}" && "$driver" != "none" && -z "$db_create_cmd" ]]; then
            if [[ "$driver" == "sqlite" ]]; then
                update_env_key "$env_file" "DB_DATABASE" "$db_target"
            else
                update_env_key "$env_file" "DB_DATABASE" "$db_name"
            fi
        fi
        write_marker "$env_file" "$branch" "$offset" "$db_name"
        register_offset "$registry_file" "$branch" "$offset" "$db_name"
    else
        echo "[dry-run] would update .env and register offset $offset"
        local cfg_key env_key rendered
        for cfg_key in "${!CONFIG[@]}"; do
            [[ "$cfg_key" == env_updates.* ]] || continue
            env_key="${cfg_key#env_updates.}"
            rendered="$(render_env_refs "${CONFIG[$cfg_key]}" "$env_refs_file")"
            rendered="$(render_template "$rendered" ctx)"
            echo "[dry-run] env: $env_key=$rendered"
        done
    fi

    # Install and build.
    run_commands install ctx
    run_commands build ctx
    # In dry-run, also show what serve/destroy hooks would do.
    if [[ $DRY_RUN -eq 1 ]]; then
        run_commands serve ctx
        run_commands destroy ctx
    fi

    # Report: reflect what actually happened, and only detail the ports the
    # project config actually references.
    local -A used_ports
    collect_used_ports used_ports

    local -A port_labels=(
        [app]=APP_PORT [db]=FORWARD_DB_PORT [vite]=VITE_PORT
        [serve]=SERVE_PORT [redis]=REDIS_PORT [mailhog]=MAILHOG_PORT
    )
    local -a unused=()

    echo ""
    echo "── worktree-bootstrap report ─────────────────────────────"
    echo "  branch .............. $branch"
    case "$db_action" in
        skipped*|"") echo "  database ............ ${db_action:-skipped}" ;;
        would\ *)    echo "  database ............ $db_name (dry-run)" ;;
        created\ via*) echo "  database ............ $db_name ($db_action)" ;;
        already\ *)  echo "  database ............ $db_name ($db_action)" ;;
        *)           echo "  database ............ $db_name" ;;
    esac
    local pkey
    for pkey in app db vite serve redis mailhog; do
        if [[ -n "${used_ports[$pkey]:-}" ]]; then
            printf '  %-22s %s\n' "${port_labels[$pkey]} ............" "${ports[$pkey]}"
        else
            unused+=("$pkey")
        fi
    done
    if [[ ${#unused[@]} -gt 0 ]]; then
        echo "  unused ports ........ ${unused[*]} (allocated)"
    fi
    echo "──────────────────────────────────────────────────────────"
}

cmd_create() {
    local branch="$1"
    local main_root worktree_path
    main_root="$(resolve_main_root "$MAIN_ROOT_OVERRIDE")"
    worktree_path="$(dirname "$main_root")/$(basename "$main_root")-${branch//\//-}"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] would create worktree $worktree_path for branch $branch"
        if ! git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
            echo "[dry-run] branch '$branch' does not exist; would create from ${BASE_REF:-HEAD}"
        fi
        # Render the full bootstrap plan without creating anything.
        WORKTREE_ROOT_OVERRIDE="$worktree_path"
        BRANCH_OVERRIDE="$branch"
        cmd_bootstrap
        return 0
    fi

    create_worktree "$branch" "$worktree_path" "$BASE_REF"

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
    if [[ -z "${db_name:-}" ]]; then
        db_name="$(get_config database.name_prefix)$(slugify "$branch")"
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

    local -A ctx
    build_context ctx "$branch" "$branch_slug" "$site" "$db_name" "$worktree_path" "$main_root" ports

    run_commands destroy ctx

    if [[ $DRY_RUN -eq 0 ]]; then
        local db_drop_cmd
        db_drop_cmd="$(get_config database.drop)"
        if [[ -n "$db_drop_cmd" ]]; then
            local rendered_drop
            rendered_drop="$(render_template "$db_drop_cmd" ctx)"
            info "running: $rendered_drop"
            eval "$rendered_drop" || warn "database.drop command failed: $rendered_drop"
        elif [[ "$driver" == "none" ]]; then
            : # DB handling disabled.
        elif [[ -n "${db_name:-}" ]] && db_driver_available "$driver"; then
            db_drop "$driver" "$db_name" || warn "failed to drop database $db_name"
        fi
        remove_worktree "$worktree_path"
        # Prune immediately so the branch is deletable right away.
        git -C "$main_root" worktree prune
        if [[ $DELETE_BRANCH -eq 1 && "$branch" != "unknown" ]]; then
            git -C "$main_root" branch -D "$branch" 2>/dev/null \
                || warn "could not delete branch $branch (checked out elsewhere?)"
        fi
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
        if [[ $DELETE_BRANCH -eq 1 && "$branch" != "unknown" ]]; then
            echo "[dry-run] would delete branch $branch"
        fi
    fi
}
