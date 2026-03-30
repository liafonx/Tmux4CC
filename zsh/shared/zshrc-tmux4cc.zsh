# tmux4cc shell integration — sourced from ~/.zshrc before oh-my-zsh
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/shared/zshrc-tmux4cc.zsh

# ─── tmux auto-start ─────────────────────────────────────────────────────────

# Start tmux automatically for interactive login shells that aren't already in tmux.
# SKIP_TMUX=1 bypasses this (used in scripts and remote tmux source-file calls).
# Prefer the most recently active claude/codex window in same dir, then zsh, else new.
if [[ -z $TMUX && -z $SKIP_TMUX && $- == *i* && -t 0 ]]; then
  match=$(tmux list-windows -a -F "#{session_activity}|#{session_name}:#{window_index}|#{pane_current_path}|#{pane_current_command}" 2>/dev/null \
    | sort -t'|' -k1 -rn \
    | awk -F"|" -v d="$PWD" '
      $3==d && ($4~/^[0-9]+\.[0-9]+\.[0-9]+$/ || $4~/^codex/ || $4=="claude") && !ai {ai=$2}
      $3==d && $4=="zsh" && !zsh {zsh=$2}
      END {if(ai) print ai; else if(zsh) print zsh}')
  if [[ -n "$match" ]]; then
    exec tmux attach-session -t "$match"
  else
    exec tmux new-session -As "${PWD##*/}"
  fi
fi

# ─── TERM guard ──────────────────────────────────────────────────────────────

# Inside tmux, force TERM to tmux-256color so tools see the correct capabilities.
[[ -n $TMUX ]] && export TERM=tmux-256color

# ─── cd auto-attach + session rename ─────────────────────────────────────────

# On cd: rename current session to dir basename; switch to existing AI window in
# the target dir if one exists (across all sessions).
_tmux4cc_chpwd() {
  [[ -z $TMUX ]] && return
  # Rename current session to the new directory basename
  tmux rename-session "${PWD##*/}" 2>/dev/null
  # Switch to existing AI window in the target dir (across all sessions)
  local cur_sess cur_win match
  cur_sess=$(tmux display-message -p '#{session_name}')
  cur_win=$(tmux display-message -p '#{window_index}')
  match=$(tmux list-windows -a -F '#{session_name}:#{window_index}|#{pane_current_path}|#{pane_current_command}' \
    | awk -F'|' -v d="$PWD" -v cs="$cur_sess" -v cw="$cur_win" \
      '$2==d && ($3~/^[0-9]+\.[0-9]+\.[0-9]+$/ || $3~/^codex/ || $3=="claude") {
        split($1, a, ":"); if (a[1]!=cs || a[2]!=cw) {print $1; exit}
      }')
  [[ -n "$match" ]] && tmux switch-client -t "$match"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _tmux4cc_chpwd
