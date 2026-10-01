# Tmux4CC

Shell installer suite for running Claude Code inside tmux across three machines. No build system, no package manager.

## Machines

| Machine    | OS     | Arch   | User      | Access                           |
|------------|--------|--------|-----------|----------------------------------|
| MacBook    | macOS  | arm64  | `liafo`   | local                            |
| Mac Mini   | macOS  | x86_64 | `liafonx` | `liafonx@Liafonxs-Mac-mini.local`|
| Linux VPS  | Ubuntu | amd64  | `liafonx` | `liafonx@88.151.34.29`           |

## File Types

| Pattern | Description |
|---------|-------------|
| `*.sh` | Executable scripts — run with `bash <script>.sh` |
| `*-agent.md` | Agent instruction files — paste into Claude Code to run as autonomous agent |
| `must-user-actions.md` | Human checklist for steps requiring manual interaction |
| `tmux.conf` | Tmux configuration deployed to `~/.config/tmux/tmux.conf` |

## Status

All three machines are fully set up. Do not re-run `install-tmux.sh`, `zsh-preflight-agent.md`, or `setup-ntfy-server.sh`.

## Deploy

**tmux.conf** — deploy and reload on both remotes:
```bash
scp tmux.conf liafonx@Liafonxs-Mac-mini.local:~/.config/tmux/tmux.conf && \
  ssh liafonx@Liafonxs-Mac-mini.local -- 'SKIP_TMUX=1 /bin/bash --norc -c "/usr/local/bin/tmux source ~/.config/tmux/tmux.conf"'
scp tmux.conf liafonx@88.151.34.29:~/.config/tmux/tmux.conf && \
  ssh liafonx@88.151.34.29 'SKIP_TMUX=1 tmux source ~/.config/tmux/tmux.conf'
```

**Claude Code hooks (Bark push)** — symlink + settings.json merge locally, then SCP + install on both remotes:
```bash
bash scripts/deploy.sh --hooks
```
New machine: copy the repo, add `BARK_SERVER` / `BARK_DEVICE_KEY` to `~/.zsh_secrets`, then run `bash scripts/install-claude-hooks.sh` and `bash hooks/notify.sh --test`.

## Lint

```bash
shellcheck hooks/notify.sh scripts/install-claude-hooks.sh scripts/deploy.sh scripts/tmux-cleanup.sh
bash -n hooks/notify.sh && bash -n scripts/install-claude-hooks.sh
```
