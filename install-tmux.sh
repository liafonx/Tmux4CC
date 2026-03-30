#!/usr/bin/env bash
set -euo pipefail

# ─── OS / arch detection ──────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Detected OS: $OS, ARCH: $ARCH"

case "${OS}/${ARCH}" in
  Darwin/arm64)   PLATFORM="macos-arm64" ;;
  Darwin/x86_64)  PLATFORM="macos-x86_64" ;;
  Linux/x86_64)   PLATFORM="linux-x86_64" ;;
  Linux/aarch64)  PLATFORM="linux-aarch64" ;;
  *)
    echo "Error: unsupported OS/arch combination: ${OS}/${ARCH}" >&2
    exit 1
    ;;
esac

echo "Platform: $PLATFORM"

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

# ─── Write ~/.claude/hooks/notify.sh ─────────────────────────────────────────

echo "Writing ~/.claude/hooks/notify.sh..."
backup_file ~/.claude/hooks/notify.sh

cat > ~/.claude/hooks/notify.sh << 'EOF'
#!/usr/bin/env bash
# ~/.claude/hooks/notify.sh
# Receives JSON on stdin from Claude Code hooks — sends meaningful content to ntfy

input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // "event"')
session=$(echo "$input" | jq -r '.session_id // "claude"' | cut -c1-8)

case "$event" in
  Notification)
    title=$(echo "$input" | jq -r '.title // "Claude Code"')
    msg=$(echo "$input" | jq -r '.message // "Needs attention"')
    ntfy_title="$title"
    ntfy_msg="[$session] $msg"
    ntype=$(echo "$input" | jq -r '.notification_type // ""')
    case "$ntype" in
      permission_prompt) ntfy_priority="high" ;;
      idle_prompt)       ntfy_priority="default" ;;
      *)                 ntfy_priority="default" ;;
    esac
    ;;
  Stop)
    ntfy_title="Claude Code Stopped"
    raw_msg=$(echo "$input" | jq -r '.last_assistant_message // "Session ended"')
    if [[ ${#raw_msg} -gt 500 ]]; then
      last_msg="${raw_msg:0:500}…"
    else
      last_msg="$raw_msg"
    fi
    ntfy_msg="[$session] $last_msg"
    ntfy_priority="low"
    ;;
  *)
    ntfy_title="Claude Code"
    ntfy_msg="[$session] $event"
    ntfy_priority="default"
    ;;
esac

# Phone notification via self-hosted ntfy — primary channel, works everywhere
NTFY_HEADERS=(-H "Title: $ntfy_title" -H "Priority: $ntfy_priority")
[[ -n "${NTFY_TOKEN:-}" ]] && NTFY_HEADERS+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
curl -s -X POST "${NTFY_URL}/${NTFY_TOPIC}" \
  "${NTFY_HEADERS[@]}" \
  -d "$ntfy_msg" &>/dev/null &

# Desktop notification (macOS) — secondary channel for local sessions
if command -v terminal-notifier &>/dev/null; then
  terminal-notifier -title "$ntfy_title" -message "$ntfy_msg" -sound default
elif command -v osascript &>/dev/null; then
  osascript -e "display notification \"$ntfy_msg\" with title \"$ntfy_title\""
fi
EOF

chmod +x ~/.claude/hooks/notify.sh
echo "Wrote ~/.claude/hooks/notify.sh"

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
