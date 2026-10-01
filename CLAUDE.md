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
shellcheck hooks/notify.sh scripts/install-claude-hooks.sh scripts/deploy.sh scripts/tmux-cleanup.sh scripts/install-tmux.sh scripts/setup-ntfy-server.sh
bash -n <script>
```

All `.sh` files must pass `shellcheck` and `bash -n`.

## File types

- `*.sh` — executable scripts, run with `bash <script>.sh`
- `*-agent.md` — agent instruction files for Claude Code (not runnable scripts). Paste into Claude Code to execute as an autonomous agent.
- `must-user-actions.md` — human checklist for steps requiring manual interaction

## Repo structure

```
tmux/           — tmux config: tmux.conf (core), integrations.conf (Claude/Codex), status-bar.conf
zsh/shared/     — shared zsh files sourced on all machines (zshenv, tmux4cc integration, aliases, completions)
zsh/overlays/   — per-machine zsh additions: macbook.zsh, macmini.zsh, linux-vps.zsh
hooks/          — Claude Code hooks: notify.sh (Bark push) + claude-hooks.json (settings.json fragment)
scripts/        — deploy.sh, install-claude-hooks.sh, tmux-cleanup.sh, archived installers
server/bark/    — self-hosted bark-server on the VPS: compose.yml + Caddy site
```

## Setup status

| Machine | Status | Notes |
|---------|--------|-------|
| MacBook | **done** | tmux.conf via symlink, .zshrc patched, hooks live |
| Mac Mini | **done** | tmux.conf via SCP, .zshrc patched, hooks deployed |
| Linux VPS | **done** | tmux.conf via SCP, .zshrc patched, hooks deployed |

**All three machines are fully set up.** Do not re-run `install-tmux.sh`, `zsh-preflight-agent.md`, or `setup-ntfy-server.sh`. For any further changes, edit config files directly (locally or via SSH) and SCP/reload as needed.

## hooks/notify.sh (Bark push)

Claude Code hook → [Bark](https://github.com/Finb/bark) iOS push via the self-hosted server `https://bark.liafonx.net`. Works in the CLI and the Desktop app's Code tab (both read `~/.claude/settings.json` hooks).

**What pushes** — main agent only; any hook input with `.agent_id` (subagent) is dropped:
- `PreToolUse` `AskUserQuestion` → ❓ Question
- `PreToolUse` `ExitPlanMode` → 📋 Plan ready
- `Stop` → ✅ Finished, **only if no more work is coming**: `background_tasks` and `session_crons` (incl. `/loop` wakeups) in the Stop input are both empty, and `stop_hook_active` isn't true.

**Layout** — title `Claude Code · <host>`, subtitle = session name (transcript `custom-title`, else project), body = the status only (`✅ Finished`, `❓ Question`, `📋 Plan ready`). A push is a nudge to go back to the computer, not a reading view — don't add message text (it gets cut off in the iOS preview, and Bark doesn't render markdown).

Nothing else is registered (no `SubagentStop`/`Notification`/`PermissionRequest`). Hooks run with `async: true`. One push `id` per session, so a session's newest push replaces its previous one.

**Install** — `scripts/install-claude-hooks.sh` (local, idempotent): symlinks `~/.claude/hooks/notify.sh` → `<repo>/hooks/notify.sh` and merges `hooks/claude-hooks.json` into `~/.claude/settings.json` (replaces entries whose command contains `/.claude/hooks/notify.sh`, keeps everything else; `--uninstall`, `--dry-run`). `deploy.sh --hooks` runs it locally and on both remotes.

**Config** — `BARK_SERVER`, `BARK_DEVICE_KEY` (comma-separated for several devices), optional `BARK_HOST_LABEL` in `~/.zsh_secrets`. The script greps only `BARK_*` lines from that file, because Desktop-app sessions don't inherit the shell env. Debug: `BARK_DRY_RUN=1` prints the payload, `BARK_DEBUG=1` logs raw hook input to `$TMPDIR/cc-bark-debug.jsonl`. Smoke test: `bash ~/.claude/hooks/notify.sh --test`.

**New machine** — copy the repo, add the `BARK_*` lines to `~/.zsh_secrets`, run `bash scripts/install-claude-hooks.sh`, then `notify.sh --test`.

**Server** — `server/bark/compose.yml` runs at `~/bark-server` on the VPS (`docker compose up -d`, port `127.0.0.1:8087`); `server/bark/bark.liafonx.net.caddy` goes in `/etc/caddy/sites-available/` (wildcard cert, needs sudo). The old ntfy setup is retired (Caddy site `.disabled`).

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

Use `scripts/deploy.sh` for automated deployment. **Run from MacBook only** — deploys local symlinks then SCPs to both remotes.

```bash
bash scripts/deploy.sh [--all | --tmux | --zsh | --hooks | --cleanup] [--dry-run]
```

Manual SCP commands below for reference:

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
| `hooks/` | `~/.config/tmux4cc/hooks/` → then run `scripts/install-claude-hooks.sh` there (links `~/.claude/hooks/notify.sh`, merges settings.json) |
| `scripts/tmux-cleanup.sh` | `~/.tmux/cleanup.sh` |
| `server/bark/*` | VPS only: `~/bark-server/` |

## Gotchas

- **`scp -r` trailing slash**: Never `scp -r src/ dst/` — copies the dir itself into dst, creating `dst/src/` nested dirs. Use `scp -r src dst/parent/` instead.
- **Mac Mini `~/.secrets`**: That path is a certbot directory. Credentials live in `~/.zsh_secrets` on **all** machines.
- **Credentials file**: `~/.zsh_secrets` (chmod 600) on all machines, sourced by `zsh/shared/zshenv.zsh`.
- **tmux config test**: OMZ wraps the `tmux` binary in interactive zsh. For reload testing inside an existing session use: `TMUX="" /opt/homebrew/bin/tmux source-file ~/.config/tmux/tmux.conf`
- **`~/.config/tmux4cc`**: MacBook = symlink to repo root. Remotes = real directory. `tmux/tmux.conf` source-files reference this path — must exist before config reload works.

## Conventions

- All scripts use `set -euo pipefail` and `#!/usr/bin/env bash`
- Heredocs use single-quoted `'EOF'` to prevent variable expansion (except when expansion is intentional)
- Scripts must be idempotent — safe to re-run
- Backup existing files to `<file>.pre-tmux4cc.bak` before overwriting
