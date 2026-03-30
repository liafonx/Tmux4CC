# tmux4cc shell integration — sourced from ~/.zshrc before oh-my-zsh
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/shared/zshrc-tmux4cc.zsh

# ─── tmux auto-start ─────────────────────────────────────────────────────────

# Start tmux automatically for interactive login shells that aren't already in tmux.
# SKIP_TMUX=1 bypasses this (used in scripts and remote tmux source-file calls).
if [[ -z "$TMUX" && -z "$SKIP_TMUX" && "$-" == *i* ]]; then
  exec tmux new-session -A -s cc
fi

# ─── TERM guard ──────────────────────────────────────────────────────────────

# Inside tmux, force TERM to tmux-256color so tools see the correct capabilities.
[[ -n "$TMUX" ]] && export TERM=tmux-256color

# ─── cd auto-attach + session rename ─────────────────────────────────────────

# When changing directories inside tmux, rename the current window to the
# new directory's basename and update the pane title.
_tmux4cc_chpwd() {
  [[ -z "$TMUX" ]] && return
  local dir="${PWD##*/}"
  tmux rename-window "$dir"
  printf '\033]2;%s\033\\' "$dir"
}

# Register hook (zsh chpwd hook runs after every cd).
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _tmux4cc_chpwd
