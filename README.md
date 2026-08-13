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

## How ports are allocated

The tool keeps a registry at `<main-repo>/.worktree-bootstrap/ports.tsv`. It
reuses the same offset for a branch, reclaims free offsets, or allocates a new
one above the highest registered offset. Base ports come from the config file.

## License

MIT
