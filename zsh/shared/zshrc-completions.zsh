# Guarded completions — sourced from ~/.zshrc after oh-my-zsh
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/shared/zshrc-completions.zsh
# All entries are no-ops if the tool is not installed.

command -v kubectl &>/dev/null && source <(kubectl completion zsh)
command -v uv &>/dev/null && eval "$(uv generate-shell-completion zsh)"
command -v uvx &>/dev/null && eval "$(uvx --generate-shell-completion zsh)"

# bun completions
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
