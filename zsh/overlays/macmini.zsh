# Mac Mini overlay — macOS x86_64, user: liafonx
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/overlay.zsh
# Sourced from ~/.zshenv after zsh/shared/zshenv.zsh.

path=(
  /usr/local/opt/curl/bin
  /usr/local/opt/postgresql@16/bin
  "$HOME/.local/bin"
  "$HOME/.bun/bin"
  $path
)

export ENABLE_CORRECTION="true"
export COMPLETION_WAITING_DOTS="true"

# incr.zsh — incremental completion (Mac Mini only)
[[ -f /etc/oh-my-zsh/custom/plugins/incr/incr.zsh ]] && source /etc/oh-my-zsh/custom/plugins/incr/incr.zsh
