# MacBook overlay — macOS arm64, user: liafo
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/overlay.zsh
# Sourced from ~/.zshenv after zsh/shared/zshenv.zsh.

path=(
  "$HOME/.local/bin"
  "$HOME/.bun/bin"
  "$HOME/.orbstack/bin"
  "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
  "$HOME/.cargo/bin"
  "$HOME/.claude/bin"
  "$HOME/Library/Android/sdk/platform-tools"
  "$HOME/.ghcup/bin"
  $path
)

# Go — cache GOPATH to avoid a subprocess on every shell start.
# To re-detect after a Go reinstall: unset GOPATH in a new shell.
export GOPATH="${GOPATH:-$(go env GOPATH 2>/dev/null)}"
[[ -n "$GOPATH" ]] && path+=("$GOPATH/bin")

export ANDROID_HOME="$HOME/Library/Android/sdk"
export RANDOOP_PATH="/usr/local/etc/randoop-4.3.3"
export RANDOOP_JAR="/usr/local/etc/randoop-4.3.3/randoop-all-4.3.3.jar"
export ENABLE_LSP_TOOL=1
