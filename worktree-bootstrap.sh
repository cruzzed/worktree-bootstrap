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
