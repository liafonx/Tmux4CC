# Linux VPS overlay — Ubuntu amd64, user: liafonx
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/overlay.zsh
# Sourced from ~/.zshenv after zsh/shared/zshenv.zsh.

path=(
  "$HOME/.local/bin"
  "$HOME/.bun/bin"
  $path
)

export NTFY_PORT=2586
export BUN_INSTALL="$HOME/.bun"
