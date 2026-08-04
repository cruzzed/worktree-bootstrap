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
  bootstrap --main-repo <path>
                         Bootstrap the current worktree directory.
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
