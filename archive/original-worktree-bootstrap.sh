#!/usr/bin/env bash
#
# worktree-bootstrap — local worktree bootstrap for Pixalink Explore.
#
# Run this from inside a freshly created git worktree. It will:
#   1. Copy .env, Passport OAuth keys, and Claude settings from the main repo.
#   2. Create a branch-named database and clone the main DB into it.
#   3. Allocate unique ports per worktree (APP_PORT, FORWARD_DB_PORT, VITE_PORT, etc.).
#   4. Install composer and npm dependencies, then build assets.
#   5. Print a report with the database, ports, and serve command.
#
# This script intentionally does NOT touch .claude/skills/worktree-setup/;
# that skill is for the lead's Macbook workflow. This is the local non-Mac
# alternative that clones the existing database instead of starting empty.
#
# Usage:
#   bash ~/.local/bin/worktree-bootstrap.sh
#   bash ~/.local/bin/worktree-bootstrap.sh /path/to/main/repo
#   bash ~/.local/bin/worktree-bootstrap.sh --dry-run
#   bash ~/.local/bin/worktree-bootstrap.sh --check-redis --check-mailhog
#
# Exit codes: 0 = ok, 1 = fatal.

set -uo pipefail

# --- Help manual -------------------------------------------------------------
show_help() {
    cat <<'EOF'
worktree-bootstrap — local worktree bootstrap for Pixalink Explore
==================================================================

PURPOSE
-------
Run this from inside a freshly created git worktree. It prepares the
worktree for local development by:

  1. Copying .env, Passport OAuth keys, and Claude settings from the main repo.
  2. Creating a branch-named MySQL database and cloning the main DB into it.
  3. Allocating unique ports per worktree so multiple worktrees can run at once.
  4. Installing PHP/JS dependencies and building frontend assets.
  5. Printing a final report with the database, ports, and serve commands.

This script is intentionally separate from .claude/skills/worktree-setup/;
that skill is for the lead's Macbook workflow. This is the local non-Mac
alternative that clones the existing database instead of starting empty.

PREREQUISITES
-------------
  • Run from inside a git worktree, not the main repo root.
  • The main repo must have a .env file with working DB credentials.
  • mysql and mysqldump CLI tools must be available to clone the database.
  • composer, npm, and node must be available to install and build.

USAGE
-----
  bash ~/.local/bin/worktree-bootstrap.sh [OPTIONS] [MAIN_REPO_PATH]

POSITIONAL ARGUMENT
-------------------
  MAIN_REPO_PATH        Optional path to the main Pixalink repo. If omitted,
                        the script auto-detects it from the worktree's git
                        common directory.

OPTIONS
-------
  --dry-run             Preview what the script would do without making any
                        changes. No files are copied, no DB is created, and
                        no dependencies are installed.

  --force-clone         If the target database already exists, drop it and
                        re-clone from the main DB. Without this flag, an
                        existing target DB is left as-is.

  --check-redis         Include the per-worktree Redis port when checking for
                        available offsets. Use this only if you plan to run a
                        separate Redis instance for this worktree.

  --check-mailhog       Include the per-worktree MailHog port when checking for
                        available offsets. Use this only if you plan to run a
                        separate MailHog instance for this worktree.

  --help                Show this help message and exit.

HOW IT WORKS
------------
ENV COPY
  The script copies these files from the main repo into the worktree:
    • .env
    • storage/oauth-private.key
    • storage/oauth-public.key
    • .claude/settings.local.json (if present)

DATABASE CLONE
  The target DB name is derived from the current branch name:
    feature/shopify-credit  ->  explore_feature_shopify_credit
    hotfix/abc-123          ->  explore_hotfix_abc_123

  Special characters are replaced with underscores and the result is truncated
  to 60 characters to stay within MySQL's 64-byte database-name limit.

  The script runs:
    CREATE DATABASE IF NOT EXISTS <target_db>;
    mysqldump --single-transaction <source_db> | mysql <target_db>

  This preserves all schema, data, OAuth clients, and user credentials from the
  main repo database.

PORT ALLOCATION
  Ports are derived from an integer offset. The script maintains a registry at:
    <main-repo>/.worktree-bootstrap/ports.tsv

  Base ports:
    APP_PORT          = 8080 + offset
    FORWARD_DB_PORT   = 33060 + offset
    VITE_PORT         = 5173 + offset
    SERVE_PORT        = 8000 + offset   (for php artisan serve --port=...)
    REDIS_PORT        = 6379 + offset   (optional, see --check-redis)
    MAILHOG_PORT      = 1025 + offset   (optional, see --check-mailhog)

  The script:
    1. Reuses the existing offset for this branch if one is registered.
    2. Otherwise tries to reclaim an unused registered offset whose ports are free.
    3. Otherwise increments from the highest registered offset, testing ports
       until it finds a free set.

  The marker line written to the worktree .env is:
    # WORKTREE_BOOTSTRAP=branch:<branch>:offset:<offset>:db:<db_name>

IDEMPOTENCY
-----------
Re-running the script is safe. It detects the WORKTREE_BOOTSTRAP marker and
reuses the same offset and database name. Use --force-clone if you want to
refresh the database from the main repo.

TYPICAL AGENT INVOCATION
------------------------
  1. Create the worktree:
       git worktree add ../Pixalink-Explore-<branch> <branch>

  2. Change into the worktree:
       cd ../Pixalink-Explore-<branch>

  3. Preview the bootstrap:
       bash ~/.local/bin/worktree-bootstrap.sh --dry-run

  4. Run the bootstrap:
       bash ~/.local/bin/worktree-bootstrap.sh

  5. Serve the app:
       php artisan serve --port=<SERVE_PORT from report>
       npm run dev

TROUBLESHOOTING
---------------
  "FATAL: you are running this from the main repo root."
    -> cd into a git worktree first.

  "FATAL: .env not found"
    -> The main repo is missing .env. Create it there before bootstrapping.

  "WARN: mysql/mysqldump CLI not found"
    -> Install the MySQL client tools, or create the target DB manually.

  "WARN: database <name> already exists; skipping clone"
    -> Use --force-clone to replace it, or leave it as-is.

  "WARN: ports for registered offset N appear to be in use"
    -> Another process is using the ports assigned to this branch. Stop that
       process, or delete the branch's line from .worktree-bootstrap/ports.tsv
       to force a new offset assignment.

EXIT CODES
----------
  0  Success (or successful dry-run)
  1  Fatal error (missing .env, failed DB clone, failed install/build, etc.)
EOF
    exit 0
}

# --- Parse args --------------------------------------------------------------
DRY_RUN=0
FORCE_CLONE=0
CHECK_REDIS=0
CHECK_MAILHOG=0
MAIN_ROOT_OVERRIDE=""

for arg in "$@"; do
    case "$arg" in
        --help|-h) show_help ;;
        --dry-run) DRY_RUN=1 ;;
        --force-clone) FORCE_CLONE=1 ;;
        --check-redis) CHECK_REDIS=1 ;;
        --check-mailhog) CHECK_MAILHOG=1 ;;
        *) MAIN_ROOT_OVERRIDE="$arg" ;;
    esac
done

WORKTREE_ROOT="$(pwd)"

# --- Resolve main repo root --------------------------------------------------
if [[ -n "$MAIN_ROOT_OVERRIDE" ]]; then
    MAIN_ROOT="$MAIN_ROOT_OVERRIDE"
else
    COMMON_GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
        echo "FATAL: not inside a git repository." >&2
        exit 1
    }
    MAIN_ROOT="$(dirname "$COMMON_GIT_DIR")"
fi

if [[ "$WORKTREE_ROOT" == "$MAIN_ROOT" ]]; then
    echo "FATAL: you are running this from the main repo root." >&2
    echo "       Create a worktree first: git worktree add ../Pixalink-Explore-<branch> <branch>" >&2
    exit 1
fi

# --- Helper: read a value from .env ------------------------------------------
env_value() {
    local file="$1"
    local key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | sed -E "s/^${key}=//" | sed -E "s/^['\"](.*)['\"]$/\1/"
}

# --- Helper: slugify a branch name for MySQL ---------------------------------
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g' | sed -E 's/^_|_$//g' | cut -c1-60
}

# --- Preflight ---------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
BRANCH_SLUG="$(slugify "$BRANCH")"
DB_NAME="explore_${BRANCH_SLUG}"
FORCE_CLONE_FLAG=""

if [[ $FORCE_CLONE -eq 1 ]]; then
    FORCE_CLONE_FLAG=" (force clone enabled)"
fi

echo "── worktree-bootstrap preflight ──────────────────────────"
echo "  worktree : $WORKTREE_ROOT"
echo "  main repo: $MAIN_ROOT"
echo "  branch   : $BRANCH"
echo "  target db: $DB_NAME${FORCE_CLONE_FLAG}"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "  mode     : DRY RUN (no changes)"
fi
echo "──────────────────────────────────────────────────────────"

if [[ ! -f "$MAIN_ROOT/.env" ]]; then
    echo "FATAL: $MAIN_ROOT/.env not found — cannot bootstrap without it." >&2
    exit 1
fi

# --- Copy config files -------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
    cp "$MAIN_ROOT/.env" "$WORKTREE_ROOT/.env" || {
        echo "FATAL: failed to copy .env" >&2
        exit 1
    }
    echo "copied: .env"

    mkdir -p "$WORKTREE_ROOT/.claude" "$WORKTREE_ROOT/storage"

    if [[ -f "$MAIN_ROOT/.claude/settings.local.json" ]]; then
        cp "$MAIN_ROOT/.claude/settings.local.json" "$WORKTREE_ROOT/.claude/settings.local.json"
        echo "copied: .claude/settings.local.json"
    fi

    if [[ -f "$MAIN_ROOT/storage/oauth-private.key" && -f "$MAIN_ROOT/storage/oauth-public.key" ]]; then
        cp "$MAIN_ROOT/storage/oauth-private.key" "$MAIN_ROOT/storage/oauth-public.key" "$WORKTREE_ROOT/storage/" || {
            echo "FATAL: failed to copy oauth keys" >&2
            exit 1
        }
        echo "copied: storage/oauth-{private,public}.key"
    fi
else
    echo "[dry-run] would copy .env, settings.local.json, and oauth keys"
fi

# --- Read DB credentials from .env -------------------------------------------
# In dry-run mode the worktree .env has not been copied yet, so read from main repo.
if [[ $DRY_RUN -eq 0 ]]; then
    ENV_FILE="$WORKTREE_ROOT/.env"
else
    ENV_FILE="$MAIN_ROOT/.env"
fi

DB_HOST="$(env_value "$ENV_FILE" DB_HOST)"
DB_PORT="$(env_value "$ENV_FILE" DB_PORT)"
DB_USERNAME="$(env_value "$ENV_FILE" DB_USERNAME)"
DB_PASSWORD="$(env_value "$ENV_FILE" DB_PASSWORD)"
SOURCE_DB="$(env_value "$ENV_FILE" DB_DATABASE)"

if [[ -z "$SOURCE_DB" ]]; then
    echo "FATAL: could not read DB_DATABASE from copied .env" >&2
    exit 1
fi

echo "  source db: $SOURCE_DB"

# --- Database clone ----------------------------------------------------------
MYSQL_CLIENT="mysql"
MYSQLDUMP="mysqldump"

if ! command -v "$MYSQL_CLIENT" >/dev/null 2>&1 || ! command -v "$MYSQLDUMP" >/dev/null 2>&1; then
    echo "WARN: mysql/mysqldump CLI not found. Skipping DB clone." >&2
    echo "      Create and populate the database manually:" >&2
    echo "      CREATE DATABASE $DB_NAME;" >&2
    echo "      mysqldump -h$DB_HOST -P$DB_PORT -u$DB_USERNAME -p... $SOURCE_DB | mysql -h$DB_HOST -P$DB_PORT -u$DB_USERNAME -p... $DB_NAME" >&2
else
    MYSQL_ARGS="-h$DB_HOST -P$DB_PORT -u$DB_USERNAME"
    if [[ -n "$DB_PASSWORD" ]]; then
        MYSQL_ARGS="$MYSQL_ARGS -p$DB_PASSWORD"
    fi

    # Check if target DB already exists
    DB_EXISTS=0
    if echo "SHOW DATABASES LIKE '$DB_NAME';" | $MYSQL_CLIENT $MYSQL_ARGS | grep -q "$DB_NAME"; then
        DB_EXISTS=1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ $DB_EXISTS -eq 1 ]]; then
            echo "[dry-run] target DB exists; would skip clone (use --force-clone to overwrite)"
        else
            echo "[dry-run] would create DB $DB_NAME and clone $SOURCE_DB into it"
        fi
    else
        if [[ $DB_EXISTS -eq 1 && $FORCE_CLONE -eq 0 ]]; then
            echo "WARN: database $DB_NAME already exists; skipping clone."
            echo "      Use --force-clone to drop and re-clone it."
        else
            if [[ $DB_EXISTS -eq 1 && $FORCE_CLONE -eq 1 ]]; then
                echo "dropping existing database: $DB_NAME"
                echo "DROP DATABASE IF EXISTS \`$DB_NAME\`;" | $MYSQL_CLIENT $MYSQL_ARGS || {
                    echo "FATAL: failed to drop existing database $DB_NAME" >&2
                    exit 1
                }
            fi

            echo "creating database: $DB_NAME"
            echo "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | $MYSQL_CLIENT $MYSQL_ARGS || {
                echo "FATAL: failed to create database $DB_NAME" >&2
                exit 1
            }

            echo "cloning $SOURCE_DB -> $DB_NAME (this may take a while)..."
            $MYSQLDUMP --single-transaction $MYSQL_ARGS "$SOURCE_DB" | $MYSQL_CLIENT $MYSQL_ARGS "$DB_NAME" || {
                echo "FATAL: failed to clone database" >&2
                exit 1
            }
            echo "cloned: $SOURCE_DB -> $DB_NAME"
        fi
    fi
fi

# --- Update .env with target DB ----------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
    if grep -qE "^DB_DATABASE=" "$ENV_FILE"; then
        sed -i -E "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$ENV_FILE"
    else
        echo "DB_DATABASE=$DB_NAME" >> "$ENV_FILE"
    fi
    echo "updated: DB_DATABASE=$DB_NAME"
else
    echo "[dry-run] would set DB_DATABASE=$DB_NAME"
fi

# --- Port allocation ---------------------------------------------------------
REGISTRY_DIR="$MAIN_ROOT/.worktree-bootstrap"
REGISTRY_FILE="$REGISTRY_DIR/ports.tsv"

mkdir -p "$REGISTRY_DIR"
touch "$REGISTRY_FILE"

# Try to reuse existing offset for this branch
EXISTING_OFFSET=""
if [[ -f "$REGISTRY_FILE" ]]; then
    EXISTING_OFFSET="$(grep -E "^${BRANCH}\t" "$REGISTRY_FILE" 2>/dev/null | head -n1 | cut -f2)"
fi

# Compute ports for a given offset
compute_ports() {
    local off="$1"
    APP_PORT=$((8080 + off))
    FORWARD_DB_PORT=$((33060 + off))
    VITE_PORT=$((5173 + off))
    SERVE_PORT=$((8000 + off))
    REDIS_PORT=$((6379 + off))
    MAILHOG_PORT=$((1025 + off))
}

# Check if a TCP port is listening on 127.0.0.1
port_in_use() {
    local port="$1"
    (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null
}

# Check if the core ports for an offset are free.
# Serve ports are the primary target; Redis/MailHog are only checked when requested
# because most developers run a single shared Redis/MailHog instance.
offset_ports_available() {
    local off="$1"
    compute_ports "$off"
    local ports=("$APP_PORT" "$FORWARD_DB_PORT" "$VITE_PORT" "$SERVE_PORT")
    [[ $CHECK_REDIS -eq 1 ]] && ports+=("$REDIS_PORT")
    [[ $CHECK_MAILHOG -eq 1 ]] && ports+=("$MAILHOG_PORT")

    for port in "${ports[@]}"; do
        if port_in_use "$port"; then
            echo "  -> port $port busy"
            return 1
        fi
    done
    return 0
}

# Gather offsets already registered or marked in worktree .env files
registered_offsets=""
while IFS=$'\t' read -r _ off _ _; do
    [[ "$off" =~ ^[0-9]+$ ]] && registered_offsets="$registered_offsets $off"
done < "$REGISTRY_FILE"

while IFS= read -r wt_path; do
    [[ -z "$wt_path" || "$wt_path" == "$WORKTREE_ROOT" ]] && continue
    wt_env="$wt_path/.env"
    if [[ -f "$wt_env" ]]; then
        marker="$(grep -E "^# WORKTREE_BOOTSTRAP=" "$wt_env" 2>/dev/null | head -n1)"
        if [[ "$marker" =~ offset:([0-9]+) ]]; then
            registered_offsets="$registered_offsets ${BASH_REMATCH[1]}"
        fi
    fi
done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}')

if [[ -n "$EXISTING_OFFSET" ]]; then
    OFFSET="$EXISTING_OFFSET"
    compute_ports "$OFFSET"
    echo "reusing registered offset: $OFFSET"
    if ! offset_ports_available "$OFFSET"; then
        echo "WARN: ports for registered offset $OFFSET appear to be in use." >&2
        echo "      You may need to stop another process or clear the registry entry." >&2
    fi
else
    # Find the first offset whose ports are all free, preferring unused offsets first
    OFFSET=""
    for off in $(echo "$registered_offsets" | tr ' ' '\n' | sort -n -u); do
        if offset_ports_available "$off"; then
            OFFSET="$off"
            echo "reclaiming unused registered offset: $OFFSET"
            break
        fi
    done

    # If no reclaimed offset is free, increment from the highest registered one
    if [[ -z "$OFFSET" ]]; then
        MAX_OFFSET=0
        for off in $registered_offsets; do
            [[ "$off" =~ ^[0-9]+$ ]] && (( off > MAX_OFFSET )) && MAX_OFFSET=$off
        done

        off=$((MAX_OFFSET + 1))
        while true; do
            if offset_ports_available "$off"; then
                OFFSET="$off"
                echo "allocated new offset: $OFFSET"
                break
            fi
            echo "  offset $off ports in use, trying next..."
            off=$((off + 1))
            if [[ $off -gt 1000 ]]; then
                echo "FATAL: could not find a free offset after 1000 attempts." >&2
                exit 1
            fi
        done
    fi
fi

compute_ports "$OFFSET"

update_env_key() {
    local key="$1"
    local value="$2"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        sed -i -E "s/^${key}=.*/${key}=${value}/" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

if [[ $DRY_RUN -eq 0 ]]; then
    update_env_key "APP_PORT" "$APP_PORT"
    update_env_key "FORWARD_DB_PORT" "$FORWARD_DB_PORT"
    update_env_key "VITE_PORT" "$VITE_PORT"

    # Marker for idempotency
    sed -i '/^# WORKTREE_BOOTSTRAP=/d' "$ENV_FILE"
    echo "# WORKTREE_BOOTSTRAP=branch:${BRANCH}:offset:${OFFSET}:db:${DB_NAME}" >> "$ENV_FILE"

    # Register branch in main-repo registry
    grep -vE "^${BRANCH}\t" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" 2>/dev/null || true
    printf "%s\t%s\t%s\t%s\n" "$BRANCH" "$OFFSET" "$DB_NAME" "$(date -Iseconds)" >> "$REGISTRY_FILE.tmp"
    mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"

    echo "allocated ports: APP_PORT=$APP_PORT, FORWARD_DB_PORT=$FORWARD_DB_PORT, VITE_PORT=$VITE_PORT"
else
    echo "[dry-run] would allocate offset $OFFSET -> APP_PORT=$APP_PORT, FORWARD_DB_PORT=$FORWARD_DB_PORT, VITE_PORT=$VITE_PORT"
fi

# --- Install dependencies ----------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] would run composer install (background) and npm ci, then npm run build"
    echo ""
    echo "── worktree-bootstrap dry-run report ─────────────────────"
    echo "  branch       : $BRANCH"
    echo "  source db    : $SOURCE_DB"
    echo "  target db    : $DB_NAME"
    echo "  APP_PORT     : $APP_PORT"
    echo "  FORWARD_DB_PORT: $FORWARD_DB_PORT"
    echo "  VITE_PORT    : $VITE_PORT"
    echo "  SERVE_PORT   : $SERVE_PORT (php artisan serve --port=$SERVE_PORT)"
    echo "  REDIS_PORT   : $REDIS_PORT (only if you run per-worktree Redis)"
    echo "  MAILHOG_PORT : $MAILHOG_PORT (only if you run per-worktree MailHog)"
    echo "──────────────────────────────────────────────────────────"
    exit 0
fi

composer_log="$(mktemp "${TMPDIR:-/tmp}/worktree-composer.XXXXXX")"
echo "→ composer install (background, log: $composer_log)"
composer install >"$composer_log" 2>&1 &
composer_pid=$!

echo "→ npm ci"
npm_ci_status=0
npm ci || npm_ci_status=$?

echo "→ waiting for composer install to finish…"
composer_status=0
wait "$composer_pid" || composer_status=$?
if [[ $composer_status != 0 ]]; then
    echo "── composer install FAILED — output: ──" >&2
    cat "$composer_log" >&2
fi
rm -f "$composer_log"

# --- Build assets ------------------------------------------------------------
build_status=0
build_state="OK"
if [[ $npm_ci_status != 0 ]]; then
    build_state="skipped (npm ci failed)"
elif [[ $composer_status != 0 ]]; then
    build_state="skipped (composer install failed)"
else
    echo "→ npm run build"
    if ! npm run build; then
        build_status=$?
        build_state="FAILED ($build_status)"
    fi
fi

# --- Passport keys fallback --------------------------------------------------
if [[ ! -f "$WORKTREE_ROOT/storage/oauth-private.key" && $composer_status -eq 0 ]]; then
    echo "→ generating Passport keys (none copied from main repo)"
    php artisan passport:keys || echo "WARN: passport:keys failed — API/OAuth tests may 500." >&2
fi

# --- Report ------------------------------------------------------------------
echo ""
echo "── worktree-bootstrap report ─────────────────────────────"
echo "  branch .............. $BRANCH"
echo "  database ............ $DB_NAME (cloned from $SOURCE_DB)"
echo "  APP_PORT ............ $APP_PORT"
echo "  FORWARD_DB_PORT ..... $FORWARD_DB_PORT"
echo "  VITE_PORT ........... $VITE_PORT"
echo "  SERVE_PORT .......... $SERVE_PORT"
echo "  Redis (optional) .... $REDIS_PORT"
echo "  MailHog (optional) .. $MAILHOG_PORT"
echo "  composer install .... $([[ $composer_status -eq 0 ]] && echo OK || echo "FAILED ($composer_status)")"
echo "  npm ci .............. $([[ $npm_ci_status -eq 0 ]] && echo OK || echo "FAILED ($npm_ci_status)")"
echo "  npm run build ....... $build_state"
echo ""
echo "  serve this worktree:"
echo "    php artisan serve --port=$SERVE_PORT"
echo "    npm run dev         (uses VITE_PORT=$VITE_PORT)"
echo ""
echo "  run migrations if needed:"
echo "    php artisan migrate"
echo "──────────────────────────────────────────────────────────"

if [[ $composer_status -eq 0 && $npm_ci_status -eq 0 && $build_status -eq 0 ]]; then
    exit 0
else
    exit 1
fi
