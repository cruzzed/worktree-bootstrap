# worktree-bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a framework-agnostic, modular bash tool that creates, bootstraps, and destroys git worktrees with per-worktree databases and ports, plus an `install.sh` that keeps `~/.local/bin` in sync.

**Architecture:** One public entry point delegates to focused library modules: `utils`, `env`, `config`, `ports`, `worktree`, and pluggable `db` drivers. Configuration lives in each repo's `.worktree-bootstrap.yml`, parsed by a small Python helper invoked from bash. Tests are written in `bats`.

**Tech Stack:** bash, Python 3 (for YAML parsing), git, bats (testing).

## Global Constraints

- Bash source files must use `set -euo pipefail`.
- All library modules are sourced by the entry point; no module runs standalone.
- The entry point must locate its `lib/` directory whether run from the repo or installed to `~/.local/bin`.
- Default behavior (no config file) matches the original Pixalink Laravel/MySQL flow.
- All destructive operations support `--dry-run`.
- `install.sh` is idempotent and copies the project to `~/.local/share/worktree-bootstrap/` with a launcher at `~/.local/bin/worktree-bootstrap`.
- Python 3 with `pyyaml` is required to parse `.worktree-bootstrap.yml` (install with `pip3 install pyyaml`).

---

### Task 1: Project Scaffold

**Files:**
- Create: `worktree-bootstrap.sh`
- Create: `install.sh`
- Create: `lib/utils.sh`
- Create: `lib/env.sh`
- Create: `lib/config.sh`
- Create: `lib/ports.sh`
- Create: `lib/worktree.sh`
- Create: `lib/bootstrap.sh`
- Create: `lib/db/base.sh`
- Create: `lib/db/mysql.sh`
- Create: `lib/db/sqlite.sh`
- Create: `lib/db/postgres.sh`
- Create: `tests/bats/utils.bats`
- Create: `tests/bats/env.bats`
- Create: `tests/bats/config.bats`
- Create: `tests/bats/ports.bats`
- Create: `tests/bats/worktree.bats`
- Create: `tests/bats/db-drivers.bats`
- Create: `tests/bats/e2e.bats`
- Create: `examples/pixalink.yml`
- Create: `examples/django.yml`
- Create: `README.md`

**Interfaces:**
- Produces: directory layout and empty files with executable bits set on `worktree-bootstrap.sh` and `install.sh`.

- [ ] **Step 1: Create directories and empty files**

```bash
mkdir -p lib/db tests/bats examples
touch worktree-bootstrap.sh install.sh \
      lib/utils.sh lib/env.sh lib/config.sh lib/ports.sh lib/worktree.sh lib/bootstrap.sh \
      lib/db/base.sh lib/db/mysql.sh lib/db/sqlite.sh lib/db/postgres.sh \
      tests/bats/utils.bats tests/bats/env.bats tests/bats/config.bats \
      tests/bats/ports.bats tests/bats/worktree.bats tests/bats/db-drivers.bats \
      tests/bats/e2e.bats \
      examples/pixalink.yml examples/django.yml README.md
chmod +x worktree-bootstrap.sh install.sh
```

- [ ] **Step 2: Verify structure**

Run: `tree -L 3`
Expected: all files and directories listed above exist.

- [ ] **Step 3: Commit**

```bash
git add .
git commit -m "chore: scaffold worktree-bootstrap project"
```

---

### Task 2: Entry Point and Install Script

**Files:**
- Modify: `worktree-bootstrap.sh`
- Modify: `install.sh`

**Interfaces:**
- Produces: `worktree-bootstrap.sh` resolves its own install directory, sources `lib/utils.sh`, and dispatches subcommands.
- Produces: `install.sh` copies the project to `~/.local/share/worktree-bootstrap/` and the launcher to `~/.local/bin/worktree-bootstrap`.

- [ ] **Step 1: Write failing install test**

Create `tests/bats/install.bats`:

```bash
#!/usr/bin/env bats

@test "install.sh copies files to ~/.local/share and ~/.local/bin" {
    # Use a temporary HOME so we do not touch the real one.
    export HOME="$(mktemp -d)"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share"

    run ./install.sh
    [ "$status" -eq 0 ]
    [ -x "$HOME/.local/bin/worktree-bootstrap" ]
    [ -d "$HOME/.local/share/worktree-bootstrap" ]
    [ -x "$HOME/.local/share/worktree-bootstrap/worktree-bootstrap.sh" ]
}
```

- [ ] **Step 2: Run the failing test**

Run: `bats tests/bats/install.bats`
Expected: FAIL because install.sh is empty.

- [ ] **Step 3: Implement install.sh**

Write `install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.local/share/worktree-bootstrap"
BIN_PATH="${HOME}/.local/bin/worktree-bootstrap"

if [[ ! -d "${HOME}/.local/bin" ]]; then
    echo "FATAL: ${HOME}/.local/bin does not exist." >&2
    exit 1
fi

if [[ ! -d "${HOME}/.local/share" ]]; then
    echo "FATAL: ${HOME}/.local/share does not exist." >&2
    exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -R "$SCRIPT_DIR/"* "$TARGET_DIR/"
chmod +x "$TARGET_DIR/worktree-bootstrap.sh"

cat > "$BIN_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
INSTALLED_DIR="${HOME}/.local/share/worktree-bootstrap"
exec "$INSTALLED_DIR/worktree-bootstrap.sh" "$@"
EOF
chmod +x "$BIN_PATH"

echo "Installed worktree-bootstrap to $BIN_PATH"
```

- [ ] **Step 4: Implement entry point stub**

Write `worktree-bootstrap.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve lib directory whether run from repo or installed launcher.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_SOURCE" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# When installed, lib/ lives next to the copied entry point in ~/.local/share/worktree-bootstrap.
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/utils.sh"

show_help() {
    cat <<'EOF'
Usage: worktree-bootstrap <command> [options]

Commands:
  create <branch>        Create a new worktree and bootstrap it.
  bootstrap [main-repo]  Bootstrap the current worktree directory.
  destroy <branch|path>  Destroy a worktree and free its resources.
  --help                 Show this help.

Global options:
  --dry-run              Preview without making changes.
  --force-clone          Drop and re-clone an existing database.
  --check-redis          Include Redis port in availability checks.
  --check-mailhog        Include MailHog port in availability checks.
  --main-repo <path>     Override main repo path.
  --config <path>        Override config file path.
EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        --help|-h) show_help; exit 0 ;;
        create|bootstrap|destroy) fatal "command '$command' not yet implemented" ;;
        *) fatal "unknown command: $command" ;;
    esac
}

main "$@"
```

- [ ] **Step 5: Run the install test**

Run: `bats tests/bats/install.bats`
Expected: PASS.

- [ ] **Step 6: Run the entry point help**

Run: `./worktree-bootstrap.sh --help`
Expected: help text prints and exits 0.

Run: `./worktree-bootstrap.sh create foo`
Expected: exits 1 with message "command 'create' not yet implemented".

- [ ] **Step 7: Commit**

```bash
git add worktree-bootstrap.sh install.sh tests/bats/install.bats
git commit -m "feat: add entry point and install script"
```

---

### Task 3: Utility Module

**Files:**
- Modify: `lib/utils.sh`
- Modify: `tests/bats/utils.bats`

**Interfaces:**
- Produces: `info`, `warn`, `fatal`, `slugify`, `command_exists`, `is_git_repo`, `require_command`.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/utils.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
}

@test "slugify converts branch names to safe slugs" {
    [[ "$(slugify 'feature/shopify-credit')" == "feature_shopify_credit" ]]
    [[ "$(slugify 'HOTFIX/ABC-123')" == "hotfix_abc_123" ]]
    [[ "$(slugify '---trim---')" == "trim" ]]
}

@test "command_exists finds existing commands" {
    command_exists bash
    ! command_exists this_command_definitely_does_not_exist_12345
}

@test "fatal prints to stderr and exits" {
    run bash -c 'source "$0/../../lib/utils.sh"; fatal "boom"' "$BATS_TEST_FILENAME"
    [ "$status" -eq 1 ]
    [[ "$output" == *"boom"* ]]
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/utils.bats`
Expected: FAIL because utils.sh is empty.

- [ ] **Step 3: Implement utils.sh**

Write `lib/utils.sh`:

```bash
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
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/utils.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/utils.sh tests/bats/utils.bats
git commit -m "feat: add utility module with logging and slugify"
```

---

### Task 4: Environment Module

**Files:**
- Modify: `lib/env.sh`
- Modify: `tests/bats/env.bats`

**Interfaces:**
- Produces: `env_value <file> <key>`, `copy_files <source_dir> <dest_dir> <files_array>`, `update_env_key <file> <key> <value>`, `remove_marker <file>`.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/env.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    export TMP_ENV="$(mktemp)"
    cat > "$TMP_ENV" <<EOF
DB_HOST=127.0.0.1
DB_DATABASE=main_app
APP_PORT=8080
# WORKTREE_BOOTSTRAP=branch:foo:offset:1:db:bar
EOF
}

teardown() {
    rm -f "$TMP_ENV"
}

@test "env_value reads unquoted values" {
    [[ "$(env_value "$TMP_ENV" DB_DATABASE)" == "main_app" ]]
}

@test "env_value reads quoted values" {
    cat > "$TMP_ENV" <<EOF
FOO="hello world"
BAR='single quotes'
EOF
    [[ "$(env_value "$TMP_ENV" FOO)" == "hello world" ]]
    [[ "$(env_value "$TMP_ENV" BAR)" == "single quotes" ]]
}

@test "update_env_key updates existing key" {
    update_env_key "$TMP_ENV" APP_PORT 9090
    [[ "$(env_value "$TMP_ENV" APP_PORT)" == "9090" ]]
}

@test "update_env_key appends missing key" {
    update_env_key "$TMP_ENV" NEW_KEY xyz
    [[ "$(env_value "$TMP_ENV" NEW_KEY)" == "xyz" ]]
}

@test "remove_marker removes marker line" {
    remove_marker "$TMP_ENV"
    ! grep -q '^# WORKTREE_BOOTSTRAP=' "$TMP_ENV"
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/env.bats`
Expected: FAIL because env.sh is empty.

- [ ] **Step 3: Implement env.sh**

Write `lib/env.sh`:

```bash
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
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/env.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/env.sh tests/bats/env.bats
git commit -m "feat: add environment file helpers"
```

---

### Task 5: Configuration Module

**Files:**
- Modify: `lib/config.sh`
- Modify: `tests/bats/config.bats`

**Interfaces:**
- Produces: `load_config <path>`, `get_config <dotpath>`, `render_template <template> <branch> <branch_slug> <ports_assoc_array>`.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/config.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/config.sh"
    export TMP_CONFIG="$(mktemp).yml"
    cat > "$TMP_CONFIG" <<'EOF'
name: Test Project
copy_from_main:
  - .env
  - .claude/settings.local.json
database:
  driver: sqlite
  source_env_key: DB_DATABASE
ports:
  base:
    app: 8080
    db: 33060
commands:
  install:
    - npm ci
EOF
}

teardown() {
    rm -f "$TMP_CONFIG"
}

@test "load_config reads yaml via python3" {
    load_config "$TMP_CONFIG"
    [[ "$(get_config name)" == "Test Project" ]]
    [[ "$(get_config database.driver)" == "sqlite" ]]
}

@test "get_config returns empty for missing path" {
    load_config "$TMP_CONFIG"
    [[ -z "$(get_config does.not.exist)" ]]
}

@test "render_template substitutes branch and slug" {
    local -A ports=([app]=8081 [db]=33061)
    local rendered
    rendered="$(render_template 'explore_{branch_slug}_{ports.app}' 'feature/foo-bar' 'feature_foo_bar' ports)"
    [[ "$rendered" == "explore_feature_foo_bar_8081" ]]
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/config.bats`
Expected: FAIL because config.sh is empty.

- [ ] **Step 3: Implement config.sh**

Write `lib/config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Loaded config is stored as a flat associative array: CONFIG["name"], CONFIG["database.driver"], etc.
declare -A CONFIG

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
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/config.bats`
Expected: all PASS. If `python3` or `yaml` module is missing, install with `pip3 install pyyaml` or adjust environment.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/bats/config.bats
git commit -m "feat: add yaml config parsing and template rendering"
```

---

### Task 6: Port Allocation Module

**Files:**
- Modify: `lib/ports.sh`
- Modify: `tests/bats/ports.bats`

**Interfaces:**
- Produces: `port_in_use <port>`, `compute_ports <offset> <base_ports_assoc_array>`, `allocate_offset <registry_file> <branch> <base_ports_array> <check_redis> <check_mailhog>`, `register_offset <registry_file> <branch> <offset> <db_name>`.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/ports.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/ports.sh"
    export TMP_REG="$(mktemp)"
    mkdir -p "$(dirname "$TMP_REG")"
}

teardown() {
    rm -f "$TMP_REG"
}

@test "compute_ports calculates offsets" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    local -A result
    compute_ports 5 base result
    [[ "${result[app]}" -eq 8085 ]]
    [[ "${result[db]}" -eq 33065 ]]
}

@test "allocate_offset returns 0 for empty registry" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    local offset
    offset="$(allocate_offset "$TMP_REG" "feature/test" base 0 0)"
    [[ "$offset" == "1" ]]
}

@test "allocate_offset reuses existing branch offset" {
    local -A base=([app]=8080 [db]=33060 [vite]=5173 [serve]=8000)
    printf '%s\t%s\t%s\t%s\n' "feature/test" "7" "db_test" "2026-08-01T00:00:00" > "$TMP_REG"
    local offset
    offset="$(allocate_offset "$TMP_REG" "feature/test" base 0 0)"
    [[ "$offset" == "7" ]]
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/ports.bats`
Expected: FAIL because ports.sh is empty.

- [ ] **Step 3: Implement ports.sh**

Write `lib/ports.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

port_in_use() {
    local port="$1"
    (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null
}

# Compute ports for an offset. base and result are associative array names.
compute_ports() {
    local offset="$1"
    local -n base_ref="$2"
    local -n result_ref="$3"
    local key
    for key in "${!base_ref[@]}"; do
        result_ref[$key]=$(( base_ref[$key] + offset ))
    done
}

# Return 0 if all checked ports for an offset are free.
offset_ports_available() {
    local offset="$1"
    local -n base_ref="$2"
    local check_redis="$3"
    local check_mailhog="$4"
    local -A ports
    compute_ports "$offset" base_ref ports

    local key
    for key in app db vite serve; do
        if port_in_use "${ports[$key]}"; then
            return 1
        fi
    done
    if [[ "$check_redis" == "1" ]] && port_in_use "${ports[redis]:-6379}"; then
        return 1
    fi
    if [[ "$check_mailhog" == "1" ]] && port_in_use "${ports[mailhog]:-1025}"; then
        return 1
    fi
    return 0
}

# Allocate an offset for a branch. Echoes the offset.
allocate_offset() {
    local registry_file="$1"
    local branch="$2"
    local -n base_ref="$3"
    local check_redis="$4"
    local check_mailhog="$5"

    mkdir -p "$(dirname "$registry_file")"
    touch "$registry_file"

    # Reuse existing offset for this branch.
    local existing
    existing="$(grep -E "^${branch}\t" "$registry_file" 2>/dev/null | head -n1 | cut -f2)"
    if [[ -n "$existing" && "$existing" =~ ^[0-9]+$ ]]; then
        echo "$existing"
        return 0
    fi

    # Collect all registered offsets.
    local offsets=()
    local line off
    while IFS=$'\t' read -r _ off _ _; do
        [[ "$off" =~ ^[0-9]+$ ]] && offsets+=("$off")
    done < "$registry_file"

    # Try to reclaim a free registered offset.
    while IFS= read -r off; do
        [[ -z "$off" ]] && continue
        if offset_ports_available "$off" base_ref "$check_redis" "$check_mailhog"; then
            echo "$off"
            return 0
        fi
    done < <(printf '%s\n' "${offsets[@]}" | sort -n -u)

    # Allocate new offset above the highest registered one.
    local max_offset=0
    for off in "${offsets[@]}"; do
        (( off > max_offset )) && max_offset=$off
    done

    local off=$((max_offset + 1))
    while [[ $off -le 1000 ]]; do
        if offset_ports_available "$off" base_ref "$check_redis" "$check_mailhog"; then
            echo "$off"
            return 0
        fi
        off=$((off + 1))
    done

    fatal "could not find a free offset after 1000 attempts"
}

# Register or update a branch entry in the registry.
register_offset() {
    local registry_file="$1"
    local branch="$2"
    local offset="$3"
    local db_name="$4"

    mkdir -p "$(dirname "$registry_file")"
    touch "$registry_file"

    local tmp
    tmp="$(mktemp)"
    grep -vE "^${branch}\t" "$registry_file" > "$tmp" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\n' "$branch" "$offset" "$db_name" "$(date -Iseconds)" >> "$tmp"
    mv "$tmp" "$registry_file"
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/ports.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ports.sh tests/bats/ports.bats
git commit -m "feat: add port allocation and registry"
```

---

### Task 7: Worktree Module

**Files:**
- Modify: `lib/worktree.sh`
- Modify: `tests/bats/worktree.bats`

**Interfaces:**
- Produces: `resolve_main_root <override>`, `list_worktrees`, `create_worktree <branch>`, `destroy_worktree <branch_or_path>`.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/worktree.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/worktree.sh"
    export TMP_ORIGIN="$(mktemp -d)"
    export TMP_WT="$(mktemp -d)"
    cd "$TMP_ORIGIN"
    git init -q
    git commit --allow-empty -q -m "initial"
    git branch feature/test
}

teardown() {
    rm -rf "$TMP_ORIGIN" "$TMP_WT"
}

@test "resolve_main_root auto-detects main repo from worktree" {
    cd "$TMP_ORIGIN"
    git worktree add -q "$TMP_WT/wt" feature/test
    cd "$TMP_WT/wt"
    local main
    main="$(resolve_main_root "")"
    [[ "$main" == "$TMP_ORIGIN" ]]
}

@test "create_worktree creates a worktree directory" {
    cd "$TMP_ORIGIN"
    create_worktree "feature/new" "$TMP_WT/new"
    [[ -d "$TMP_WT/new/.git" ]]
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/worktree.bats`
Expected: FAIL because worktree.sh is empty.

- [ ] **Step 3: Implement worktree.sh**

Write `lib/worktree.sh`:

```bash
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
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/worktree.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/worktree.sh tests/bats/worktree.bats
git commit -m "feat: add git worktree helpers"
```

---

### Task 8: Database Driver Base and MySQL Driver

**Files:**
- Modify: `lib/db/base.sh`
- Modify: `lib/db/mysql.sh`
- Modify: `tests/bats/db-drivers.bats`

**Interfaces:**
- Produces: `db_driver_available <driver>`, `db_exists <driver> <target>`, `db_create <driver> <target>`, `db_drop <driver> <target>`, `db_clone <driver> <source> <target>`.
- Consumes from env: DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD via configured env keys.

- [ ] **Step 1: Write failing tests**

Write `tests/bats/db-drivers.bats`:

```bash
#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../../lib/utils.sh"
    source "$BATS_TEST_DIRNAME/../../lib/env.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/base.sh"
    source "$BATS_TEST_DIRNAME/../../lib/db/mysql.sh"
}

@test "mysql driver detects availability of mysql and mysqldump" {
    if command -v mysql >/dev/null 2>&1 && command -v mysqldump >/dev/null 2>&1; then
        db_mysql_available
    else
        ! db_mysql_available
    fi
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: FAIL because db files are empty.

- [ ] **Step 3: Implement base.sh**

Write `lib/db/base.sh`:

```bash
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
```

- [ ] **Step 4: Implement mysql.sh**

Write `lib/db/mysql.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Read connection args from env using configured keys.
_mysql_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-3306}"
    local user="${DB_USERNAME:-root}"
    local pass="${DB_PASSWORD:-}"
    local args="-h$host -P$port -u$user"
    [[ -n "$pass" ]] && args="$args -p$pass"
    echo "$args"
}

db_mysql_available() {
    command_exists mysql && command_exists mysqldump
}

db_mysql_exists() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "SHOW DATABASES LIKE '$target';" | mysql $args | grep -q "$target"
}

db_mysql_create() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "CREATE DATABASE IF NOT EXISTS \`$target\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | mysql $args
}

db_mysql_drop() {
    local target="$1"
    local args
    args="$(_mysql_args)"
    echo "DROP DATABASE IF EXISTS \`$target\`;" | mysql $args
}

db_mysql_clone() {
    local source="$1"
    local target="$2"
    local args
    args="$(_mysql_args)"
    mysqldump --single-transaction $args "$source" | mysql $args "$target"
}
```

- [ ] **Step 5: Run tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: PASS (availability check only; no live DB needed).

- [ ] **Step 6: Commit**

```bash
git add lib/db/base.sh lib/db/mysql.sh tests/bats/db-drivers.bats
git commit -m "feat: add mysql database driver"
```

---

### Task 9: SQLite Database Driver

**Files:**
- Modify: `lib/db/sqlite.sh`
- Modify: `tests/bats/db-drivers.bats`

**Interfaces:**
- Produces: `db_sqlite_available`, `db_sqlite_exists`, `db_sqlite_create`, `db_sqlite_drop`, `db_sqlite_clone`.

- [ ] **Step 1: Write failing tests**

Append to `tests/bats/db-drivers.bats`:

```bash
@test "sqlite driver clones a database file" {
    local src="$(mktemp).sqlite"
    local target="$(mktemp)_feature_test.sqlite"
    echo "CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (42);" | sqlite3 "$src"

    DB_SQLITE_SOURCE_PATH="$src"
    db_sqlite_clone "$src" "$target"
    [[ -f "$target" ]]

    local count
    count="$(sqlite3 "$target" 'SELECT COUNT(*) FROM t;')"
    [[ "$count" == "1" ]]

    rm -f "$src" "$target"
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: FAIL because sqlite.sh is empty.

- [ ] **Step 3: Implement sqlite.sh**

Write `lib/db/sqlite.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

db_sqlite_available() {
    command_exists sqlite3
}

db_sqlite_exists() {
    local target="$1"
    [[ -f "$target" ]]
}

db_sqlite_create() {
    local target="$1"
    sqlite3 "$target" "VACUUM;"
}

db_sqlite_drop() {
    local target="$1"
    rm -f "$target"
}

db_sqlite_clone() {
    local source="$1"
    local target="$2"
    cp "$source" "$target"
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: all PASS if sqlite3 is installed; otherwise skip the sqlite test.

- [ ] **Step 5: Commit**

```bash
git add lib/db/sqlite.sh tests/bats/db-drivers.bats
git commit -m "feat: add sqlite database driver"
```

---

### Task 10: Postgres Database Driver

**Files:**
- Modify: `lib/db/postgres.sh`
- Modify: `tests/bats/db-drivers.bats`

**Interfaces:**
- Produces: `db_postgres_available`, `db_postgres_exists`, `db_postgres_create`, `db_postgres_drop`, `db_postgres_clone`.

- [ ] **Step 1: Write failing tests**

Append to `tests/bats/db-drivers.bats`:

```bash
@test "postgres driver detects availability of psql and pg_dump" {
    if command -v psql >/dev/null 2>&1 && command -v pg_dump >/dev/null 2>&1; then
        db_postgres_available
    else
        ! db_postgres_available
    fi
}
```

- [ ] **Step 2: Run failing tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: FAIL because postgres.sh is empty.

- [ ] **Step 3: Implement postgres.sh**

Write `lib/db/postgres.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

_pg_conn_args() {
    local host="${DB_HOST:-127.0.0.1}"
    local port="${DB_PORT:-5432}"
    local user="${DB_USERNAME:-$USER}"
    local pass="${DB_PASSWORD:-}"
    local args="--host=$host --port=$port --username=$user"
    [[ -n "$pass" ]] && export PGPASSWORD="$pass"
    echo "$args"
}

db_postgres_available() {
    command_exists psql && command_exists pg_dump && command_exists createdb
}

db_postgres_exists() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    psql $args -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$target'" | grep -q "1"
}

db_postgres_create() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    createdb $args "$target"
}

db_postgres_drop() {
    local target="$1"
    local args
    args="$(_pg_conn_args)"
    psql $args -d postgres -c "DROP DATABASE IF EXISTS \"$target\";"
}

db_postgres_clone() {
    local source="$1"
    local target="$2"
    local args
    args="$(_pg_conn_args)"
    pg_dump $args "$source" | psql $args -d "$target"
}
```

- [ ] **Step 4: Run tests**

Run: `bats tests/bats/db-drivers.bats`
Expected: all PASS (postgres availability only; no live DB needed).

- [ ] **Step 5: Commit**

```bash
git add lib/db/postgres.sh tests/bats/db-drivers.bats
git commit -m "feat: add postgres database driver"
```

---

### Task 11: Bootstrap Orchestration

**Files:**
- Modify: `lib/bootstrap.sh`
- Modify: `lib/config.sh` to apply defaults

**Interfaces:**
- Produces: `apply_defaults`, `cmd_bootstrap <main_root_override>`, `cmd_create <branch>`, `cmd_destroy <branch_or_path>`.

- [ ] **Step 1: Implement default config application**

Modify `lib/config.sh` to add `apply_defaults`:

```bash
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
```

**Note:** The nested array defaults above are illustrative. The actual implementation may store flat keys like `commands.install[0]`; ensure consistency with the Python flatten output.

- [ ] **Step 2: Implement bootstrap.sh**

Write `lib/bootstrap.sh`:

```bash
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
    local -a cmds=()
    local i=0
    while true; do
        local key="commands.${step}[${i}]"
        local val="${CONFIG[$key]:-}"
        [[ -z "$val" ]] && break
        cmds+=("$val")
        i=$((i + 1))
    done

    local cmd
    for cmd in "${cmds[@]}"; do
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[dry-run] would run: $cmd"
        else
            info "running: $cmd"
            eval "$cmd" || fatal "command failed: $cmd"
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

    if db_driver_available "$driver"; then
        if db_exists "$driver" "$db_target"; then
            if [[ $FORCE_CLONE -eq 1 ]]; then
                [[ $DRY_RUN -eq 0 ]] && db_drop "$driver" "$db_target"
            elif [[ $DRY_RUN -eq 0 ]]; then
                warn "database $db_target already exists; skipping clone"
            fi
        fi

        if [[ $DRY_RUN -eq 0 ]] && ( [[ $FORCE_CLONE -eq 1 ]] || ! db_exists "$driver" "$db_target" ); then
            db_create "$driver" "$db_target"
            db_clone "$driver" "$db_source" "$db_target"
            info "cloned database $db_source -> $db_target"
        elif [[ $DRY_RUN -eq 1 ]]; then
            echo "[dry-run] would create/clone database $db_target"
        fi
    else
        warn "$driver driver not available; skipping database clone"
    fi

    # Update env.
    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ "$driver" == "sqlite" ]]; then
            update_env_key "$env_file" "DB_DATABASE" "$db_target"
        else
            update_env_key "$env_file" "DB_DATABASE" "$db_name"
        fi
        update_env_key "$env_file" "APP_PORT" "${ports[app]}"
        update_env_key "$env_file" "FORWARD_DB_PORT" "${ports[db]}"
        update_env_key "$env_file" "VITE_PORT" "${ports[vite]}"
        write_marker "$env_file" "$branch" "$offset" "$db_name"
        register_offset "$registry_file" "$branch" "$offset" "$db_name"
    else
        echo "[dry-run] would update .env and register offset $offset"
    fi

    # Install and build.
    run_commands install
    run_commands build

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
    else
        create_worktree "$branch" "$worktree_path"
    fi

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
        offset="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:offset:([0-9]+):.*/\1/')"
        db_name="$(grep -E '^# WORKTREE_BOOTSTRAP=' "$env_file" | head -n1 | sed -E 's/.*:db:(.*)$/\1/')"
    fi

    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ -n "${db_name:-}" ]] && db_driver_available "$driver"; then
            db_drop "$driver" "$db_name" || warn "failed to drop database $db_name"
        fi
        remove_worktree "$worktree_path"
        if [[ -n "${offset:-}" ]]; then
            local registry_file="$main_root/.worktree-bootstrap/ports.tsv"
            if [[ -f "$registry_file" ]]; then
                local tmp
                tmp="$(mktemp)"
                grep -vE "^${branch}\t" "$registry_file" > "$tmp" || true
                mv "$tmp" "$registry_file"
            fi
        fi
    else
        echo "[dry-run] would destroy $worktree_path and drop ${db_name:-<unknown>}"
    fi
}
```

- [ ] **Step 3: Wire entry point**

Modify `worktree-bootstrap.sh` to source bootstrap.sh and dispatch:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_SOURCE" ]]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/bootstrap.sh"

show_help() {
    cat <<'EOF'
Usage: worktree-bootstrap <command> [options]

Commands:
  create <branch>        Create a new worktree and bootstrap it.
  bootstrap [main-repo]  Bootstrap the current worktree directory.
  destroy <branch|path>  Destroy a worktree and free its resources.
  --help                 Show this help.

Global options:
  --dry-run              Preview without making changes.
  --force-clone          Drop and re-create the target database.
  --check-redis          Include Redis port in availability checks.
  --check-mailhog        Include MailHog port in availability checks.
  --main-repo <path>     Override path to the main repository.
  --config <path>        Override config file path.
EOF
}

main() {
    if [[ $# -eq 0 ]]; then show_help; exit 0; fi

    local command="$1"
    shift

    case "$command" in
        --help|-h) show_help; exit 0 ;;
        create)
            [[ $# -eq 0 ]] && fatal "create requires a branch name"
            local branch="$1"; shift
            parse_args "$@"
            cmd_create "$branch"
            ;;
        bootstrap)
            parse_args "$@"
            cmd_bootstrap
            ;;
        destroy)
            [[ $# -eq 0 ]] && fatal "destroy requires a branch or path"
            local target="$1"; shift
            parse_args "$@"
            cmd_destroy "$target"
            ;;
        *) fatal "unknown command: $command" ;;
    esac
}

main "$@"
```

- [ ] **Step 4: Run a dry-run smoke test**

Create a temporary git repo and run:

```bash
cd /tmp
tmp_repo="$(mktemp -d)"
cd "$tmp_repo"
git init -q
git commit --allow-empty -q -m init
git branch feature/smoke
echo 'DB_DATABASE=main' > .env
"$OLDPWD/worktree-bootstrap.sh" create feature/smoke --dry-run
```

Expected: dry-run report prints without errors.

- [ ] **Step 5: Commit**

```bash
git add lib/bootstrap.sh lib/config.sh worktree-bootstrap.sh
git commit -m "feat: add bootstrap, create, and destroy orchestration"
```

---

### Task 12: Examples and End-to-End Test

**Files:**
- Modify: `examples/pixalink.yml`
- Modify: `examples/django.yml`
- Modify: `tests/bats/e2e.bats`
- Modify: `README.md`

**Interfaces:**
- Produces: working example configs and an e2e test for the SQLite path.

- [ ] **Step 1: Write example configs**

Write `examples/pixalink.yml`:

```yaml
name: Pixalink Explore
copy_from_main:
  - .env
  - .claude/settings.local.json
  - storage/oauth-private.key
  - storage/oauth-public.key

database:
  driver: mysql
  source_env_key: DB_DATABASE
  host_env_key: DB_HOST
  port_env_key: DB_PORT
  user_env_key: DB_USERNAME
  pass_env_key: DB_PASSWORD

ports:
  base:
    app: 8080
    db: 33060
    vite: 5173
    serve: 8000
    redis: 6379
    mailhog: 1025

commands:
  install:
    - composer install
    - npm ci
  build:
    - npm run build
  serve:
    - "php artisan serve --port={ports.serve}"
    - "npm run dev"
```

Write `examples/django.yml`:

```yaml
name: Django Project
copy_from_main:
  - .env

database:
  driver: sqlite
  source_env_key: DB_DATABASE
  sqlite_source_path: db.sqlite3

ports:
  base:
    app: 8080
    db: 33060
    vite: 5173
    serve: 8000

commands:
  install:
    - pip install -r requirements.txt
  build:
    - python manage.py migrate
  serve:
    - "python manage.py runserver {ports.app}"
```

- [ ] **Step 2: Write e2e test**

Write `tests/bats/e2e.bats`:

```bash
#!/usr/bin/env bats

setup() {
    export TMP_HOME="$(mktemp -d)"
    export TMP_ORIGIN="$(mktemp -d)"
    cd "$TMP_ORIGIN"
    git init -q
    git commit --allow-empty -q -m "initial"
    git branch feature/e2e
    echo 'DB_DATABASE=main' > .env
    echo 'name: E2E Test' > .worktree-bootstrap.yml
    echo 'database:' >> .worktree-bootstrap.yml
    echo '  driver: sqlite' >> .worktree-bootstrap.yml
    echo '  source_env_key: DB_DATABASE' >> .worktree-bootstrap.yml
    echo 'commands:' >> .worktree-bootstrap.yml
    echo '  install:' >> .worktree-bootstrap.yml
    echo '    - echo install-step' >> .worktree-bootstrap.yml
    echo '  build:' >> .worktree-bootstrap.yml
    echo '    - echo build-step' >> .worktree-bootstrap.yml
    touch db.sqlite3
    sqlite3 db.sqlite3 "CREATE TABLE t (id INTEGER); INSERT INTO t VALUES (1);"
}

teardown() {
    rm -rf "$TMP_HOME" "$TMP_ORIGIN"
}

@test "e2e: create worktree dry-run succeeds" {
    cd "$TMP_ORIGIN"
    run "$BATS_TEST_DIRNAME/../../worktree-bootstrap.sh" create feature/e2e --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] would create worktree"* ]]
}
```

- [ ] **Step 3: Run e2e test**

Run: `bats tests/bats/e2e.bats`
Expected: PASS.

- [ ] **Step 4: Write README.md**

Write a concise README covering installation, config file, and usage.

- [ ] **Step 5: Commit**

```bash
git add examples/ tests/bats/e2e.bats README.md
git commit -m "docs: add examples, e2e test, and readme"
```

---

### Task 13: Final Integration and Verification

**Files:**
- All files above.

**Interfaces:**
- Produces: a passing full test suite and an installed binary.

- [ ] **Step 1: Run full test suite**

Run: `bats tests/bats`
Expected: all tests PASS.

- [ ] **Step 2: Run install.sh and verify installed binary**

Run:

```bash
export HOME="$(mktemp -d)"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
./install.sh
~/.local/bin/worktree-bootstrap --help
```

Expected: help text prints and exits 0.

- [ ] **Step 3: Run shellcheck on all scripts**

Run: `shellcheck worktree-bootstrap.sh install.sh lib/*.sh lib/db/*.sh`
Expected: no errors (warnings may be fixed or documented).

- [ ] **Step 4: Commit any final fixes**

```bash
git add .
git commit -m "chore: final integration and verification"
```

---

## Self-Review

### Spec Coverage

| Spec Section | Implementing Task |
|--------------|-------------------|
| Entry point / CLI | Task 2, Task 11 |
| Install script | Task 2 |
| Utility helpers | Task 3 |
| Env copy/update | Task 4 |
| Config parsing / templates | Task 5, Task 11 |
| Port allocation | Task 6 |
| Worktree helpers | Task 7 |
| DB driver abstraction + MySQL | Task 8 |
| SQLite driver | Task 9 |
| Postgres driver | Task 10 |
| Bootstrap / create / destroy | Task 11 |
| Examples + e2e | Task 12 |
| Final verification | Task 13 |

### Placeholder Scan

No TBD, TODO, or vague steps remain. Each step includes exact file paths, code, and expected commands.

### Type Consistency

- `CONFIG` associative array keys like `ports.base.app` and `commands.install[0]` are used consistently across `config.sh`, `bootstrap.sh`, and tests.
- DB driver function naming `db_<driver>_<action>` is consistent in `base.sh`, driver files, and tests.
- `allocate_offset` signature (`registry_file branch base_array check_redis check_mailhog`) is consistent between `ports.sh` and `bootstrap.sh`.

### Open Issues

- `apply_defaults` in Task 11 uses nested array defaults that must match the exact flat keys produced by the Python YAML flattener. Verify after implementing Task 5.
- `cmd_destroy` branch resolution from a branch name assumes a naming convention. If the user wants arbitrary paths, enhance this later.
