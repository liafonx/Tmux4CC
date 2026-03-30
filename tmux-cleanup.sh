#!/usr/bin/env bash
set -euo pipefail

# Ensure tmux is in PATH (Homebrew on macOS, standard locations on Linux).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Kill unattached tmux sessions based on idle time.
# - Sessions with only zsh windows: kill after 10 minutes
# - Sessions with AI (claude/codex) windows: kill after 3 hours
# Designed to run via cron and tmux hooks.

MAX_IDLE=${TMUX_CLEANUP_MAX_IDLE:-10800}       # 3 hours in seconds
MAX_IDLE_ZSH=${TMUX_CLEANUP_MAX_IDLE_ZSH:-600} # 10 minutes in seconds
now=$(date +%s)

tmux list-sessions -F '#{session_name}|#{session_activity}|#{session_attached}' 2>/dev/null | \
while IFS='|' read -r name activity attached; do
  [[ "$attached" -ne 0 ]] && continue
  idle=$((now - activity))

  # Check if session has any non-zsh window (claude, codex, semver process)
  has_ai=$(tmux list-windows -t "$name" -F '#{pane_current_command}' 2>/dev/null \
    | grep -cvE '^zsh$' || true)

  if [[ "$has_ai" -gt 0 ]]; then
    threshold=$MAX_IDLE
  else
    threshold=$MAX_IDLE_ZSH
  fi

  if [[ "$idle" -gt "$threshold" ]]; then
    tmux kill-session -t "$name" 2>/dev/null && \
      tmux display-message "Cleaned: $name (idle $((idle/60))m)" 2>/dev/null
  fi
done || true
