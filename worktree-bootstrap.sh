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

Global options (may appear in any position):
  --dry-run              Preview without making changes.
  --force-clone          Drop and re-create the target database.
  --check-redis          Include Redis port in availability checks.
  --check-mailhog        Include MailHog port in availability checks.
  --main-repo <path>     Override path to the main repository.
  --config <path>        Override config file path.
  --base <ref>           Base ref for a new branch (create only; default: HEAD).
  --delete-branch        Also delete the branch after destroy.
EOF
}

main() {
    if [[ $# -eq 0 ]]; then show_help; exit 0; fi

    # Parse flags in any position; first positional is the command, the rest
    # are its arguments.
    local command=""
    local -a positionals=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) show_help; exit 0 ;;
            --dry-run) DRY_RUN=1 ;;
            --force-clone) FORCE_CLONE=1 ;;
            --check-redis) CHECK_REDIS=1 ;;
            --check-mailhog) CHECK_MAILHOG=1 ;;
            --delete-branch) DELETE_BRANCH=1 ;;
            --main-repo) shift; [[ $# -gt 0 ]] || fatal "--main-repo requires a value"; MAIN_ROOT_OVERRIDE="$1" ;;
            --config) shift; [[ $# -gt 0 ]] || fatal "--config requires a value"; CONFIG_PATH_OVERRIDE="$1" ;;
            --base) shift; [[ $# -gt 0 ]] || fatal "--base requires a value"; BASE_REF="$1" ;;
            -*) fatal "unknown option: $1" ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    positionals+=("$1")
                fi
                ;;
        esac
        shift
    done

    case "$command" in
        "") show_help; exit 0 ;;
        create)
            [[ ${#positionals[@]} -ge 1 ]] || fatal "create requires a branch name"
            cmd_create "${positionals[0]}"
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        destroy)
            [[ ${#positionals[@]} -ge 1 ]] || fatal "destroy requires a branch or path"
            cmd_destroy "${positionals[0]}"
            ;;
        *) fatal "unknown command: $command" ;;
    esac
}

main "$@"
