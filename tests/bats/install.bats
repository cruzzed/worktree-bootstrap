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
