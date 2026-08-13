# worktree-bootstrap

A framework-agnostic tool for creating, bootstrapping, and destroying git
worktrees with per-worktree databases and unique local ports.

## Why

When you maintain a project with long-lived feature branches, you often want a
separate checkout, database, and set of ports for each branch. This script
automates that:

1. Creates a git worktree for a branch.
2. Copies secrets and environment files from the main repo.
3. Allocates a unique set of local ports.
4. Creates a new database and clones the main one into it.
5. Runs install and build commands.
6. Provides a matching `destroy` command to tear everything down.

It works with Laravel/PHP + MySQL, Django/Python + SQLite/Postgres, or any
project that can describe its needs in a `.worktree-bootstrap.yml` config file.

## Install

```bash
./install.sh
```

This copies the project to `~/.local/share/worktree-bootstrap/` and installs a
launcher at `~/.local/bin/worktree-bootstrap`. Run it again any time you update
the repo to replace the installed copy.

## Requirements

- bash
- git
- Python 3 + PyYAML (`pip3 install pyyaml`)
- For MySQL: `mysql` and `mysqldump`
- For Postgres: `psql`, `pg_dump`, and `createdb`
- For SQLite: `sqlite3`

## Quick start

1. Add `.worktree-bootstrap.yml` to your project root (see `examples/`).
2. From the main repo, create and bootstrap a worktree:
   ```bash
   worktree-bootstrap create feature/my-branch
   ```
3. Change into the new worktree and run the serve commands from the report.
4. When done, destroy it:
   ```bash
   worktree-bootstrap destroy feature/my-branch
   ```

## Commands

```bash
worktree-bootstrap create <branch>        # create + bootstrap a worktree
worktree-bootstrap bootstrap              # bootstrap the current directory
worktree-bootstrap destroy <branch|path>  # remove worktree, DB, and ports
worktree-bootstrap --help                 # show help
```

Global options:

- `--dry-run` — preview without making changes
- `--force-clone` — drop and re-clone an existing database
- `--check-redis` — include Redis port in availability checks
- `--check-mailhog` — include MailHog port in availability checks
- `--main-repo <path>` — override main repo path
- `--config <path>` — override config file path

## Config file

Each project adds `.worktree-bootstrap.yml` at its root. If omitted, the tool
falls back to Laravel/MySQL defaults.

```yaml
name: My Project

copy_from_main:
  - .env

env_updates:
  DB_DATABASE: "myapp_{branch_slug}"
  APP_PORT: "{ports.app}"

database:
  driver: mysql          # mysql | sqlite | postgres
  name_prefix: myapp_    # worktree DBs are named {name_prefix}{branch_slug}
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

commands:
  install:
    - npm ci
  build:
    - npm run build
  serve:
    - "npm run dev"
```

Available templates in `env_updates` and `commands`:

- `{branch}` — raw branch name
- `{branch_slug}` — database-safe slug
- `{site}` — lowercased worktree directory basename (e.g. the Valet site name)
- `{ports.app}`, `{ports.db}`, `{ports.vite}`, `{ports.serve}`, `{ports.redis}`, `{ports.mailhog}`

`commands.destroy` (optional) runs before the worktree is torn down — useful
for cleanup such as `valet unsecure "{site}"`. Hook failures abort teardown, so
end best-effort commands with `|| true`.

`env_updates` entries are applied to the worktree's `.env` after it is copied
from the main repo. They override the built-in defaults: the tool only writes
`DB_DATABASE` (the cloned database name), `APP_PORT`, `FORWARD_DB_PORT`, and
`VITE_PORT` itself when you don't set that key in `env_updates`.

If you define `commands.install` or `commands.build`, the built-in defaults
(`composer install`, `npm ci`, `npm run build`) are replaced entirely, not
merged.

## Serving with Valet (optional)

If [Laravel Valet](https://laravel.com/docs/valet) (or valet-linux-plus on
Linux) parks the parent directory of your worktrees (`valet park ~/www`), each
worktree is automatically served at `https://{worktree-dir}.test` — no per-
branch serve command or port needed. Use the `{site}` template to wire TLS and
`APP_URL` per worktree:

```yaml
env_updates:
  APP_URL: "https://{site}.test"

commands:
  build:
    - npm run build
    - "command -v valet >/dev/null && valet secure \"{site}\" || true"
  destroy:
    - "command -v valet >/dev/null && valet unsecure \"{site}\" || true"
```

`valet secure`/`unsecure` restart nginx internally, so create/destroy may
prompt for the sudo password.

## How ports are allocated

The tool keeps a registry at `<main-repo>/.worktree-bootstrap/ports.tsv`. It
reuses the same offset for a branch, reclaims free offsets, or allocates a new
one above the highest registered offset. Base ports come from the config file.

## License

MIT
