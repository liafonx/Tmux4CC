# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Shell-only (bash) installer suite for running Claude Code inside tmux across three machines. No build system, no package manager.

## Machines

| Machine | OS | Arch | User | Access |
|---------|-----|------|------|--------|
| MacBook | macOS | arm64 | `liafo` | local |
| Mac Mini | macOS | x86_64 | `liafonx` | `liafonx@Liafonxs-Mac-mini.local` |
| Linux VPS | Ubuntu | amd64 | `liafonx` | `liafonx@88.151.34.29` |

Scripts run locally on each machine — no remote sudo.

## Lint

```bash
shellcheck install-tmux.sh setup-ntfy-server.sh
bash -n install-tmux.sh && bash -n setup-ntfy-server.sh
```

All `.sh` files must pass `shellcheck` and `bash -n`.

## File types

- `*.sh` — executable scripts, run with `bash <script>.sh`
- `*-agent.md` — agent instruction files for Claude Code (not runnable scripts). Paste into Claude Code to execute as an autonomous agent.
- `must-user-actions.md` — human checklist for steps requiring manual interaction
- `tmux.conf` — tmux configuration deployed to `~/.config/tmux/tmux.conf` on each machine

## Setup status

| Machine | Status | Notes |
|---------|--------|-------|
| MacBook | **done** | tmux.conf via symlink, .zshrc patched, hooks live |
| Mac Mini | **done** | tmux.conf via SCP, .zshrc patched, hooks deployed |
| Linux VPS | **done** | tmux.conf via SCP, .zshrc patched, hooks deployed |

**All three machines are fully set up.** Do not re-run `install-tmux.sh`, `zsh-preflight-agent.md`, or `setup-ntfy-server.sh`. For any further changes, edit config files directly (locally or via SSH) and SCP/reload as needed.

## hooks/notify.sh

Claude Code hook script for ntfy notifications. On the MacBook (liafo), this file is a symlink to the repo:
```
~/.claude/hooks/notify.sh -> ~/Development/GitWorkspace/Tmux4CC/hooks/notify.sh
```
Edits to the repo file take effect immediately. On Mac Mini and Linux VPS, deploy via SCP — the hook path in `~/.claude/hooks/notify.sh` must point to wherever the file lands.

## tmux.conf

Deployed to `~/.config/tmux/tmux.conf`. On the MacBook (liafo), this file is a symlink to the repo:
```
~/.config/tmux/tmux.conf -> ~/Development/GitWorkspace/Tmux4CC/tmux/tmux.conf
```
Edits to the repo file take effect immediately on this machine. On Mac Mini and Linux VPS, deploy via SCP and reload manually.

Reload without restart:
```bash
tmux source ~/.config/tmux/tmux.conf
# or inside tmux: prefix + r
```

**Key design decisions:**
- Meta/Option+key bindings (no prefix needed) for pane/window navigation
- Mouse drag auto-copies to system clipboard (pbcopy on macOS, xclip on Linux, via if-shell)
- Alternate-screen scroll sends 5 Up/Down keys (for Claude Code, vim, etc.)
- Status bar uses Catppuccin Mocha palette (`#1e1e2e` bg, `#cdd6f4` fg)
- `set-clipboard external` + OSC 52 for clipboard over SSH
- `if-shell` clipboard dispatch evaluated at source time — re-source after changing clipboard tools

**TPM plugins (install via `prefix + I`):**
| Plugin | Installed | Purpose | Key binding |
|--------|-----------|---------|-------------|
| `tmux-resurrect` | yes | Save/restore sessions across restarts | `prefix + Ctrl-s` save, `prefix + Ctrl-r` restore |
| `tmux-continuum` | yes | Auto-save every 15 min, auto-restore on attach | automatic (depends on resurrect) |
| `tmux-thumbs` | yes | Hint-based copy for visible text patterns | `prefix + Space` |
| `tmux-fuzzback` | yes | Fuzzy search scrollback buffer (requires `fzf`) | `prefix + ?` |
| `tmux-yank` | yes | Clipboard integration for copy-mode and mouse | `y` in copy mode |

Run `prefix + I` inside tmux to install all declared but missing plugins.

## Deploy

All three machines are fully deployed. When editing any config file, **always deploy to both remotes and reload**. MacBook picks up `tmux.conf` changes via symlink automatically.

Use `scripts/deploy.sh` for automated deployment. Manual SCP commands below for reference:

**tmux.conf** — deploy and reload on both remotes:
```bash
scp tmux/tmux.conf liafonx@Liafonxs-Mac-mini.local:~/.config/tmux/tmux.conf && \
  ssh liafonx@Liafonxs-Mac-mini.local -- 'SKIP_TMUX=1 /bin/bash --norc -c "/usr/local/bin/tmux source ~/.config/tmux/tmux.conf"'
scp tmux/tmux.conf liafonx@88.151.34.29:~/.config/tmux/tmux.conf && \
  ssh liafonx@88.151.34.29 'SKIP_TMUX=1 tmux source ~/.config/tmux/tmux.conf'
```

**Other files** — SCP to deployed paths on both remotes:
| Repo file | Deployed path |
|-----------|---------------|
| `hooks/notify.sh` | `~/.claude/hooks/notify.sh` |
| `scripts/tmux-cleanup.sh` | `~/.tmux/cleanup.sh` |

## Conventions

- All scripts use `set -euo pipefail` and `#!/usr/bin/env bash`
- Heredocs use single-quoted `'EOF'` to prevent variable expansion (except when expansion is intentional)
- Scripts must be idempotent — safe to re-run
- Backup existing files to `<file>.pre-tmux4cc.bak` before overwriting
