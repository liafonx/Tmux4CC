#!/usr/bin/env bash
set -euo pipefail

# install-claude-hooks.sh — wire hooks/notify.sh (Bark push) into Claude Code on THIS machine.
#
# Usage: install-claude-hooks.sh [--uninstall] [--dry-run]
#
#   1. Symlinks ~/.claude/hooks/notify.sh -> <repo>/hooks/notify.sh
#   2. Merges hooks/claude-hooks.json into ~/.claude/settings.json. Existing entries
#      that run ~/.claude/hooks/notify.sh are replaced; all other settings are kept.
#
# Idempotent. Backs up settings.json once to settings.json.pre-tmux4cc.bak.
# Works from a repo checkout (MacBook) or the deployed copy at ~/.config/tmux4cc (remotes).
# Push config (BARK_SERVER, BARK_DEVICE_KEY) lives in ~/.zsh_secrets — see zsh/secrets.example.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAGMENT="${REPO_DIR}/hooks/claude-hooks.json"
NOTIFY_SRC="${REPO_DIR}/hooks/notify.sh"
HOOK_LINK="$HOME/.claude/hooks/notify.sh"
SETTINGS="$HOME/.claude/settings.json"
# Any hook command containing this is ours.
MARKER="/.claude/hooks/notify.sh"

UNINSTALL=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    *)
      echo "Usage: install-claude-hooks.sh [--uninstall] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

command -v jq &>/dev/null || { echo "Error: jq is required" >&2; exit 1; }
[[ -f "$FRAGMENT" ]] || { echo "Error: missing $FRAGMENT" >&2; exit 1; }
[[ -f "$NOTIFY_SRC" ]] || { echo "Error: missing $NOTIFY_SRC" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ─── Symlink the hook script ──────────────────────────────────────────────────

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ -L "$HOOK_LINK" && "$(readlink "$HOOK_LINK")" == "$NOTIFY_SRC" ]]; then
    run rm "$HOOK_LINK"
    [[ "$DRY_RUN" -eq 1 ]] || echo "Removed $HOOK_LINK"
  fi
else
  run mkdir -p "$(dirname "$HOOK_LINK")"
  run chmod +x "$NOTIFY_SRC"
  run ln -sfn "$NOTIFY_SRC" "$HOOK_LINK"
  [[ "$DRY_RUN" -eq 1 ]] || echo "Linked $HOOK_LINK -> $NOTIFY_SRC"
fi

# ─── Merge hooks into settings.json ───────────────────────────────────────────

# Edit the real file if settings.json is a symlink, so the link survives.
target="$SETTINGS"
[[ -L "$SETTINGS" ]] && target="$(readlink -f "$SETTINGS")"

if [[ ! -f "$target" ]]; then
  [[ "$UNINSTALL" -eq 1 ]] && { echo "No $SETTINGS — nothing to uninstall"; exit 0; }
  run mkdir -p "$(dirname "$target")"
  if [[ "$DRY_RUN" -eq 0 ]]; then echo '{}' >"$target"; fi
fi

# shellcheck disable=SC2016  # jq program, not shell
JQ_STRIP='
  def ours: any(.hooks[]?; (.command // "") | contains($marker));
  if .hooks then
    .hooks |= (with_entries(.value |= map(select(ours | not)))
               | with_entries(select(.value | length > 0)))
    | if .hooks == {} then del(.hooks) else . end
  else . end'

# shellcheck disable=SC2016  # jq program, not shell
JQ_ADD='
  .hooks = (reduce ($frag[0].hooks | to_entries[]) as $e (.hooks // {};
              .[$e.key] = ((.[$e.key] // []) + $e.value)))'

if [[ "$UNINSTALL" -eq 1 ]]; then
  program="$JQ_STRIP"
else
  program="$JQ_STRIP | $JQ_ADD"
fi

if [[ "$DRY_RUN" -eq 1 && ! -f "$target" ]]; then
  echo "[dry-run] would create $SETTINGS with:"
  jq --arg marker "$MARKER" --slurpfile frag "$FRAGMENT" "$program" <<<'{}'
  exit 0
fi

tmp="$(mktemp "${target}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cp -p "$target" "$tmp"   # keep the original file mode
jq --arg marker "$MARKER" --slurpfile frag "$FRAGMENT" "$program" "$target" >"$tmp"
jq empty "$tmp"

if cmp -s "$target" "$tmp"; then
  echo "$SETTINGS already up to date"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] would update $SETTINGS hooks to:"
  jq '.hooks // {}' "$tmp"
  exit 0
fi

[[ -f "${target}.pre-tmux4cc.bak" ]] || cp -p "$target" "${target}.pre-tmux4cc.bak"
mv "$tmp" "$target"
trap - EXIT
if [[ "$UNINSTALL" -eq 1 ]]; then
  echo "Removed notify.sh hooks from $SETTINGS"
else
  echo "Installed notify.sh hooks into $SETTINGS (new sessions pick them up)"
fi
