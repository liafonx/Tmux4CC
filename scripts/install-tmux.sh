#!/usr/bin/env bash
set -euo pipefail

# ARCHIVED: All machines are fully set up. Do not re-run this script.
# Kept for reference. For config changes, edit files directly and use scripts/deploy.sh.

# ─── OS / arch detection ──────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Detected OS: $OS, ARCH: $ARCH"

# ─── Backup helper ────────────────────────────────────────────────────────────

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp "$f" "${f}.pre-tmux4cc.bak" && echo "Backed up $f"
}

# ─── Prerequisites ────────────────────────────────────────────────────────────

echo "Checking prerequisites..."

if [[ "$OS" == "Darwin" ]]; then
  for pkg in tmux jq terminal-notifier fzf; do
    if ! command -v "$pkg" &>/dev/null; then
      echo "Installing $pkg via brew..."
      brew install "$pkg"
    else
      echo "$pkg already installed, skipping"
    fi
  done
elif [[ "$OS" == "Linux" ]]; then
  echo "Installing prerequisites via apt-get..."
  sudo apt-get update
  sudo apt-get install -y tmux jq fzf curl xclip
fi

# ─── Directory scaffolding ────────────────────────────────────────────────────

echo "Creating directories..."
mkdir -p ~/.config/tmux/ ~/.tmux/logs/ ~/.tmux/plugins/ ~/.claude/hooks/

# ─── Consolidate plugin directory ────────────────────────────────────────────

# TPM default is ~/.tmux/plugins/. Clean up XDG location if it exists.
if [[ -d ~/.config/tmux/plugins ]]; then
  echo "Found plugins at ~/.config/tmux/plugins/, consolidating to ~/.tmux/plugins/..."
  for plugin_dir in ~/.config/tmux/plugins/*/; do
    [[ -d "$plugin_dir" ]] || continue
    plugin_name="$(basename "$plugin_dir")"
    if [[ -d "$HOME/.tmux/plugins/$plugin_name" ]]; then
      echo "  $plugin_name already exists in ~/.tmux/plugins/, skipping"
    elif [[ -L "$plugin_dir" ]]; then
      echo "  $plugin_name is a symlink, skipping"
    else
      mv "$plugin_dir" "$HOME/.tmux/plugins/$plugin_name"
      echo "  Moved $plugin_name"
    fi
  done
  rmdir ~/.config/tmux/plugins 2>/dev/null && echo "  Removed empty ~/.config/tmux/plugins/" || true
fi

# ─── Copy tmux.conf from bundle ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF_SRC="${SCRIPT_DIR}/tmux.conf"

if [[ ! -f "$TMUX_CONF_SRC" ]]; then
  echo "Error: tmux.conf not found alongside install-tmux.sh at $TMUX_CONF_SRC" >&2
  echo "Both files must be SCP'd together to the same directory." >&2
  exit 1
fi

echo "Copying tmux.conf to ~/.config/tmux/tmux.conf..."
backup_file ~/.config/tmux/tmux.conf
cp "$TMUX_CONF_SRC" ~/.config/tmux/tmux.conf
echo "Copied tmux.conf"

# ─── Write ~/.claude/keybindings.json ────────────────────────────────────────

echo "Writing ~/.claude/keybindings.json..."
backup_file ~/.claude/keybindings.json

cat > ~/.claude/keybindings.json << 'EOF'
{
  "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
  "bindings": [
    {
      "context": "Task",
      "bindings": {
        "meta+b": "task:background"
      }
    }
  ]
}
EOF

echo "Wrote ~/.claude/keybindings.json"

# notify.sh hook is now managed by hooks/notify.sh in this repo.
# Deploy via scripts/deploy.sh.

# ─── Merge hooks into ~/.claude/settings.json ────────────────────────────────

echo "Merging hooks into ~/.claude/settings.json..."

SETTINGS=~/.claude/settings.json

if [[ ! -f "$SETTINGS" ]]; then
  echo "{}" > "$SETTINGS"
  echo "Created empty $SETTINGS"
fi

# Check if notify.sh hook is already registered
existing=$(jq -r '.hooks.Notification[]?.hooks[]?.command // empty' "$SETTINGS" 2>/dev/null || true)

if echo "$existing" | grep -q "notify.sh"; then
  echo "notify.sh hooks already present in settings.json, skipping merge"
else
  backup_file "$SETTINGS"

  hooks_patch='{
    "hooks": {
      "Notification": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/.claude/hooks/notify.sh"
            }
          ]
        }
      ],
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/.claude/hooks/notify.sh"
            }
          ]
        }
      ]
    }
  }'

  tmp=$(mktemp)
  jq ". * ${hooks_patch}" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "Merged notify.sh hooks into $SETTINGS"
fi

# ─── Clone TPM ────────────────────────────────────────────────────────────────

if [[ -d ~/.tmux/plugins/tpm ]]; then
  echo "TPM already installed at ~/.tmux/plugins/tpm, skipping clone"
else
  echo "Cloning TPM..."
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  echo "Cloned TPM"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "✓ install-tmux.sh complete."
echo ""
echo "Next steps:"
echo "  1. Run zsh-preflight-agent.md with Claude Code to patch your zsh config"
echo "  2. Open tmux: tmux new-session -A -s cc"
echo "  3. Press prefix + I inside tmux to install TPM plugins"
