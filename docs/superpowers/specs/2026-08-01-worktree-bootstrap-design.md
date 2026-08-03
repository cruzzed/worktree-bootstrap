# Design: Framework-Agnostic worktree-bootstrap

## 1. Goal

Transform the existing Pixalink-specific `worktree-bootstrap.sh` into a reusable,
framework-agnostic developer tool. The new tool must support at least:

- Laravel / PHP projects using MySQL (the current use case).
- Django / Python projects using SQLite or Postgres/Neon.
- Any future project that can describe its bootstrap needs in a small config file.

The core workflow stays the same across project types:

1. Create or identify a git worktree.
2. Copy secrets/environment files from the main repo.
3. Allocate a unique set of local ports.
4. Create a new database and clone/seeds it from the main repo.
5. Run project-specific install and build commands.
6. Provide a matching `destroy` command to tear a worktree down safely.

## 2. Repository Layout

```
worktree-bootstrap/
├── worktree-bootstrap.sh      # Public entry point / CLI dispatcher.
├── install.sh                 # Copies the entry point to ~/.local/bin.
├── lib/
│   ├── bootstrap.sh           # High-level create / bootstrap / destroy orchestration.
│   ├── config.sh              # Parse .worktree-bootstrap.yml and env templates.
│   ├── env.sh                 # Read, copy, and update .env files.
│   ├── ports.sh               # Port registry and allocation.
│   ├── worktree.sh            # git worktree create / list / remove helpers.
│   ├── utils.sh               # Logging, slugify, command checks, abort/rollback.
│   └── db/
│       ├── base.sh            # Driver dispatcher and shared DB utilities.
│       ├── mysql.sh           # MySQL/mysqldump implementation.
│       ├── sqlite.sh          # SQLite file-copy implementation.
│       └── postgres.sh        # Postgres/psql (and Neon) implementation.
├── tests/
│   ├── bats/
│   │   ├── config.bats
│   │   ├── ports.bats
│   │   ├── env.bats
│   │   ├── db-drivers.bats
│   │   └── e2e.bats
│   └── fixtures/
│       ├── pixalink.yml
│       └── django.yml
└── examples/
    ├── pixalink.yml
    └── django.yml
```

## 3. Config File Format

Each project that uses the tool adds `.worktree-bootstrap.yml` to its root.
The file is optional only for projects that match built-in defaults (Laravel/MySQL),
but explicit config is recommended.

```yaml
# Optional human-readable label.
name: Pixalink Explore

# Files to copy from the main repo into the new worktree.
# Paths are relative to the repo root. Missing files are skipped with a warning.
copy_from_main:
  - .env
  - .claude/settings.local.json
  - storage/oauth-private.key
  - storage/oauth-public.key

# Key/value pairs to write or overwrite in the worktree .env after copy.
# Values support templates rendered by the bootstrapper.
# Available templates:
#   {branch}        - raw git branch name
#   {branch_slug}   - DB-safe slug of the branch name
#   {ports.app}     - allocated APP_PORT
#   {ports.db}      - allocated FORWARD_DB_PORT
#   {ports.vite}    - allocated VITE_PORT
#   {ports.serve}   - allocated SERVE_PORT
#   {ports.redis}   - allocated REDIS_PORT
#   {ports.mailhog} - allocated MAILHOG_PORT
env_updates:
  DB_DATABASE: "explore_{branch_slug}"
  APP_PORT: "{ports.app}"
  FORWARD_DB_PORT: "{ports.db}"
  VITE_PORT: "{ports.vite}"

# Database backend configuration.
database:
  driver: mysql          # mysql | sqlite | postgres
  source_env_key: DB_DATABASE
  host_env_key: DB_HOST
  port_env_key: DB_PORT
  user_env_key: DB_USERNAME
  pass_env_key: DB_PASSWORD

# Optional: path to SQLite source file, used only when driver is sqlite.
# Relative to main repo root.
# sqlite_source_path: storage/database.sqlite

# Port allocation scheme.
ports:
  base:
    app: 8080
    db: 33060
    vite: 5173
    serve: 8000
    redis: 6379
    mailhog: 1025
  # Optional extra ports to probe and expose as templates.
  extra:
    ws: 6001

# Commands to run during bootstrap.
# Each command is run in the worktree root.
commands:
  install:
    - composer install
    - npm ci
  build:
    - npm run build
  # Commands shown in the final report, not executed automatically.
  serve:
    - "php artisan serve --port={ports.serve}"
    - "npm run dev"

# Optional rollback behavior.
rollback_on_failure:
  drop_database: true
  remove_worktree: false
```

### 3.1 Default Config (Laravel/MySQL)

If no config file is found, the tool behaves like the current script:

- Copy `.env`, `.claude/settings.local.json`, `storage/oauth-*.key`.
- Use MySQL driver with default env keys.
- Use default base ports shown above.
- Run `composer install`, `npm ci`, `npm run build`.

## 4. CLI

```bash
# Create a new worktree for <branch> and bootstrap it.
worktree-bootstrap create <branch> [OPTIONS]

# Bootstrap the current directory (assumed to already be a worktree).
worktree-bootstrap bootstrap [MAIN_REPO_PATH] [OPTIONS]

# Remove a worktree, drop its database, and free its ports.
worktree-bootstrap destroy <branch|path> [OPTIONS]

# Show help.
worktree-bootstrap --help

# Global options valid for all subcommands.
--dry-run              Preview without side effects.
--force-clone          Drop and re-create the target database.
--check-redis          Include Redis port in availability checks.
--check-mailhog        Include MailHog port in availability checks.
--main-repo <path>     Override path to the main repository.
--config <path>        Override path to .worktree-bootstrap.yml.
```

### 4.1 `create` Subcommand

1. Resolve main repo root from cwd or `--main-repo`.
2. Read config from main repo.
3. Run `git worktree add ../<repo>-<branch> <branch>`.
4. Delegate to the bootstrap flow in the new worktree.

### 4.2 `bootstrap` Subcommand

1. Resolve main repo root from git common dir or argument.
2. Refuse to run if cwd equals main repo root.
3. Read config.
4. Copy files from main repo to worktree.
5. Allocate ports.
6. Create/clone database.
7. Update worktree `.env`.
8. Run install and build commands.
9. Print report.

### 4.3 `destroy` Subcommand

1. Resolve target worktree from branch name or path.
2. Read its `.env` marker line to find the allocated database and offset.
3. Drop the target database using the configured driver.
4. Remove the worktree directory with `git worktree remove`.
5. Remove the branch's entry from the port registry.

## 5. Database Driver Abstraction

Each driver is a bash module that implements the following interface:

```bash
# Return 0 if the required CLI tools are available.
db_<driver>_available() -> bool

# Return 0 if the target database exists.
db_<driver>_exists <target_name>

# Create the target database.
db_<driver>_create <target_name>

# Drop the target database.
db_<driver>_drop <target_name>

# Clone source database into target.
db_<driver>_clone <source_name> <target_name>
```

### 5.1 MySQL Driver

Uses `mysql` and `mysqldump`.

- Credentials are read from the copied `.env` using configured env keys.
- Uses `mysqldump --single-transaction <source> | mysql <target>`.
- Supports `--force-clone` to drop and re-create an existing target DB.

### 5.2 SQLite Driver

Uses simple file copy.

- Source path is taken from config (`sqlite_source_path`) or env key.
- Target path is `{source_name}_{branch_slug}.sqlite` by default.
- On `--force-clone`, overwrites the target file.

### 5.3 Postgres Driver

Uses `pg_dump` and `psql`.

- Reads connection info from env (host, port, user, password, database).
- Supports Neon connection strings via `DATABASE_URL` if present.
- Creates target DB with `createdb` or `CREATE DATABASE` via `psql`.
- Clones with `pg_dump <source> | psql <target>`.

## 6. Port Allocation

Port allocation reuses the existing registry concept but makes it config-driven.

- Registry file: `<main-repo>/.worktree-bootstrap/ports.tsv`.
- Columns: `branch`, `offset`, `database`, `updated_at`.
- Base ports are read from config; offset is added to each base.
- Idempotency marker in worktree `.env`:
  ```
  # WORKTREE_BOOTSTRAP=branch:<branch>:offset:<offset>:db:<db_name>
  ```
- Allocation algorithm:
  1. Reuse existing offset for this branch if registered.
  2. Reclaim a registered offset whose ports are all free.
  3. Allocate `max_offset + 1`, probing ports until free or cap of 1000.

## 7. Error Handling and Rollback

- Every module sources `lib/utils.sh` which sets `set -euo pipefail` and defines
  `fatal`, `warn`, `info`, and `abort_with_cleanup` helpers.
- On fatal error during `create` or `bootstrap`:
  - If `rollback_on_failure.drop_database` is true, drop the newly created DB.
  - If `rollback_on_failure.remove_worktree` is true and this was a `create`,
    run `git worktree remove` on the new worktree.
- Dry-run mode prints every planned mutation; no files, DBs, or ports are changed.

## 8. Install Script

`install.sh` installs the project so the tool can be run from anywhere.

Installation steps:

1. Copy the entire project directory to `~/.local/share/worktree-bootstrap/`.
2. Copy `worktree-bootstrap.sh` to `~/.local/bin/worktree-bootstrap`.
3. Ensure `~/.local/bin/worktree-bootstrap` is executable.

The copied entry point in `~/.local/bin` resolves its `lib/` directory relative
to `~/.local/share/worktree-bootstrap/`.

Requirements:

- Idempotent: running twice produces the same result.
- Fails loudly if `~/.local/bin` or `~/.local/share` do not exist.
- Prints a one-line summary on success.

## 9. Testing

Tests are written with `bats` and cover:

- Config parsing and template rendering.
- Slugify and env helpers.
- Port allocation in a throwaway registry.
- DB driver dispatch and availability checks.
- End-to-end flow in a temporary git repo using the SQLite driver.

CI (if added later) runs `bats tests/bats` on every change.

## 10. Open Questions

None remaining. This design was reviewed and approved by the project owner.
