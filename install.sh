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
