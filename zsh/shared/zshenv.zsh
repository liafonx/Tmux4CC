# Universal environment — sourced by ALL zsh processes (interactive and non-interactive)
# Part of tmux4cc config standardization. Deploy path: ~/.config/tmux4cc/zsh/shared/zshenv.zsh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Deduplicate PATH — prevents duplicate entries when shells are nested (e.g. tmux exec).
typeset -U path PATH

# Secrets: machine-local credentials, not in git.
# Template: zsh/secrets.example → copy to ~/.zsh_secrets, chmod 600.
[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets
