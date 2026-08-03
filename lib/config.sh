#!/usr/bin/env bash
set -euo pipefail

# Loaded config is stored as a flat associative array: CONFIG["name"], CONFIG["database.driver"], etc.
declare -gA CONFIG

# Parse YAML into flat KEY=VALUE pairs using Python, then load into CONFIG.
load_config() {
    local config_path="$1"
    if [[ ! -f "$config_path" ]]; then
        # Return silently; caller should apply defaults.
        return 0
    fi

    if ! command_exists python3; then
        fatal "python3 is required to parse .worktree-bootstrap.yml"
    fi

    local raw
    raw="$(python3 - "$config_path" <<'PY'
import sys, yaml
def flatten(obj, prefix=''):
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.extend(flatten(v, prefix + ('.' if prefix else '') + str(k)))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out.extend(flatten(v, prefix + '[' + str(i) + ']'))
    else:
        out.append((prefix, str(obj)))
    return out

try:
    data = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
if data is None:
    sys.exit(0)
for k, v in flatten(data):
    print(f'{k}={v}')
PY
    )" || fatal "failed to parse config: $config_path"

    # Clear previous config.
    CONFIG=()
    local line key value
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        CONFIG["$key"]="$value"
    done <<< "$raw"
}

# Read a dotted config path. Returns empty string if missing.
get_config() {
    local path="$1"
    echo "${CONFIG[$path]:-}"
}

# Apply default values for any keys not present in the loaded config.
apply_defaults() {
    # Defaults mirror the original Pixalink Laravel flow.
    [[ -z "${CONFIG["name"]:-}" ]] && CONFIG["name"]="worktree-bootstrap project"
    [[ -z "${CONFIG["copy_from_main[0]"]:-}" ]] && CONFIG["copy_from_main[0]"]=".env"
    [[ -z "${CONFIG["copy_from_main[1]"]:-}" ]] && CONFIG["copy_from_main[1]"]=".claude/settings.local.json"
    [[ -z "${CONFIG["copy_from_main[2]"]:-}" ]] && CONFIG["copy_from_main[2]"]="storage/oauth-private.key"
    [[ -z "${CONFIG["copy_from_main[3]"]:-}" ]] && CONFIG["copy_from_main[3]"]="storage/oauth-public.key"
    [[ -z "${CONFIG["database.driver"]:-}" ]] && CONFIG["database.driver"]="mysql"
    [[ -z "${CONFIG["database.source_env_key"]:-}" ]] && CONFIG["database.source_env_key"]="DB_DATABASE"
    [[ -z "${CONFIG["database.host_env_key"]:-}" ]] && CONFIG["database.host_env_key"]="DB_HOST"
    [[ -z "${CONFIG["database.port_env_key"]:-}" ]] && CONFIG["database.port_env_key"]="DB_PORT"
    [[ -z "${CONFIG["database.user_env_key"]:-}" ]] && CONFIG["database.user_env_key"]="DB_USERNAME"
    [[ -z "${CONFIG["database.pass_env_key"]:-}" ]] && CONFIG["database.pass_env_key"]="DB_PASSWORD"
    [[ -z "${CONFIG["database.name_prefix"]:-}" ]] && CONFIG["database.name_prefix"]="explore_"
    [[ -z "${CONFIG["ports.base.app"]:-}" ]] && CONFIG["ports.base.app"]="8080"
    [[ -z "${CONFIG["ports.base.db"]:-}" ]] && CONFIG["ports.base.db"]="33060"
    [[ -z "${CONFIG["ports.base.vite"]:-}" ]] && CONFIG["ports.base.vite"]="5173"
    [[ -z "${CONFIG["ports.base.serve"]:-}" ]] && CONFIG["ports.base.serve"]="8000"
    [[ -z "${CONFIG["ports.base.redis"]:-}" ]] && CONFIG["ports.base.redis"]="6379"
    [[ -z "${CONFIG["ports.base.mailhog"]:-}" ]] && CONFIG["ports.base.mailhog"]="1025"
    [[ -z "${CONFIG["commands.install[0]"]:-}" ]] && CONFIG["commands.install[0]"]="composer install"
    [[ -z "${CONFIG["commands.install[1]"]:-}" ]] && CONFIG["commands.install[1]"]="npm ci"
    [[ -z "${CONFIG["commands.build[0]"]:-}" ]] && CONFIG["commands.build[0]"]="npm run build"
}

# Render a template string using branch, slug, and ports associative array.
render_template() {
    local template="$1"
    local branch="$2"
    local branch_slug="$3"
    local -n ports_ref="$4"

    local result="$template"
    result="${result//\{branch\}/$branch}"
    result="${result//\{branch_slug\}/$branch_slug}"

    local key
    for key in "${!ports_ref[@]}"; do
        result="${result//\{ports.$key\}/${ports_ref[$key]}}"
    done

    echo "$result"
}
