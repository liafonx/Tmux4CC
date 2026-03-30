# Must-Do Manual Steps — tmux4CC

Scripts and agents handle most of the setup, but some actions require interactive input or hardware that can't be automated. This file lists everything you must do by hand, in order.

---

## 1. Before Running Scripts

### MacBook & Mac Mini (macOS)

Ensure Homebrew is installed:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Ensure git is installed:
```bash
xcode-select --install
# or
brew install git
```

Copy scripts to each machine:
```bash
scp install-tmux.sh tmux.conf zsh-preflight-agent.md post-verify-agent.md must-user-actions.md liafonx@Liafonxs-Mac-mini.local:~/
```

### Linux VPS

SSH in:
```bash
ssh liafonx@88.151.34.29
```

Copy scripts:
```bash
scp install-tmux.sh tmux.conf setup-ntfy-server.sh zsh-preflight-agent.md post-verify-agent.md must-user-actions.md liafonx@88.151.34.29:~/
```

Ensure `git` is installed:
```bash
sudo apt-get install -y git
```

---

## 2. After install-tmux.sh

For each machine:

1. Open a new terminal window (so the zsh preflight changes take effect)
2. If tmux auto-start isn't active yet, manually start:
   ```bash
   tmux new-session
   ```
3. **Inside tmux**, press `prefix + I` (Ctrl+B, then capital I) to trigger TPM plugin install
   - You must see "TMUX environment reloaded" before plugins are ready
   - This requires an active internet connection
4. Press `prefix + r` to reload config after plugins install

---

## 3. After setup-ntfy-server.sh (Linux VPS)

1. Note the `NTFY_URL` and `NTFY_TOPIC` printed by the script
2. Update `~/.zshenv` on **all machines** (MacBook, Mac Mini, Linux VPS) with the real values:
   ```bash
   # Replace CHANGEME placeholders in ~/.zshenv:
   export NTFY_URL="https://your-actual-domain.com"   # or http://IP
   export NTFY_TOPIC="claude-yourname-abc123"
   ```
3. Configure firewall on Linux VPS:
   ```bash
   sudo ufw allow 80/tcp   # or whatever port you chose
   sudo ufw status
   ```
4. **Optional HTTPS**: Set up a reverse proxy for TLS termination:
   - Nginx: point `ntfy.yourdomain.com` → `localhost:80`
   - Caddy: add a Caddyfile entry (handles certs automatically)
   - Once HTTPS works, update `NTFY_URL` to `https://` scheme on all machines

---

## 4. Credential Rotation (Security)

**Mac Mini** — `CF_Token` is in plaintext in `~/.zshrc`. Move it:
```bash
# Create a secrets file
touch ~/.secrets && chmod 600 ~/.secrets

# Move credentials to ~/.secrets:
echo 'export CF_Token="your-token-here"' >> ~/.secrets

# Source it from ~/.zshenv:
echo 'source ~/.secrets' >> ~/.zshenv

# Remove from ~/.zshrc (find and delete the line manually)
```

**Linux VPS** — `NORD_USERNAME`, `NORD_PASSWORD`, and `CF_Token` are plaintext in `~/.zshrc`. Same pattern:
```bash
touch ~/.secrets && chmod 600 ~/.secrets
# Move all three to ~/.secrets
echo 'export NORD_USERNAME="..."' >> ~/.secrets
echo 'export NORD_PASSWORD="..."' >> ~/.secrets
echo 'export CF_Token="..."' >> ~/.secrets
echo 'source ~/.secrets' >> ~/.zshenv
# Then remove those three lines from ~/.zshrc
```

---

## 5. ntfy Mobile App

1. Install the ntfy app:
   - iOS: App Store → "ntfy"
   - Android: F-Droid or Google Play → "ntfy"
2. In the app, tap "+" to add a subscription
3. Enter your server URL: `https://your-domain.com` (or `http://IP:port`)
4. Enter your topic name: `claude-yourname-abc123`
5. If auth is enabled, enter your credentials
6. Test: run a Claude Code task and watch for the push notification

---

## 6. Usage Guide

### Tmux Keybindings Cheat Sheet

| Binding | Action |
|---------|--------|
| `Ctrl+B d` | Detach from session (session keeps running) |
| `Ctrl+B \|` | Split pane vertically |
| `Ctrl+B -` | Split pane horizontally |
| `Ctrl+B p` | Open popup scratch shell |
| `Ctrl+B r` | Reload tmux.conf |
| `Ctrl+B L` | Toggle pane logging |
| `Ctrl+B z` | Toggle pane zoom (fullscreen) |
| `Ctrl+B Space` | tmux-thumbs: hint-based text picker |
| `Ctrl+B ?` | tmux-fuzzback: fuzzy search scrollback |
| `Ctrl+B Ctrl-S` | tmux-resurrect: save session |
| `Ctrl+B Ctrl-R` | tmux-resurrect: restore session |

### Session Management

```bash
# Attach to or create a tmux session
tmux new-session

# List sessions
tmux ls

# Detach
Ctrl+B d

# Create new named session
tmux new-session -s feature-auth

# Kill a session
tmux kill-session -t feature-auth
```

### Claude Code in tmux

```bash
# Background a long-running task (doesn't interrupt Claude)
Meta+B   # (Alt+B on most keyboards)

# Reset context between tasks
/clear

# Resume last session after CLI restart
claude --continue

# Name your session for parallel tracking
/rename auth-feature
```

### Notification Flow

```
Claude hook fires
    → notify.sh reads JSON from stdin
    → extracts session_id + hook_event_name
    → curl POST to $NTFY_URL/$NTFY_TOPIC (background, fire-and-forget)
    → terminal-notifier / osascript (macOS desktop, foreground)
    → phone receives push notification via ntfy app
```

### Parallel Workflow Pattern

```bash
# Create isolated worktrees for parallel Claude tasks
git worktree add ../project-auth feature/auth
git worktree add ../project-bugfix bugfix/login-error

# Open a tmux window for each
tmux new-window -n "auth" -c "../project-auth"
tmux new-window -n "bugfix" -c "../project-bugfix"

# In each window, start a named Claude session
claude  # then /rename auth   (in auth window)
claude  # then /rename bugfix (in bugfix window)

# Switch between them with Ctrl+B <window-number>
# Each window gets its own Claude notification when done
```

---

## Execution Order Reminder

### MacBook & Mac Mini

1. `bash install-tmux.sh`
2. Open Claude Code → paste `zsh-preflight-agent.md` content
3. Open new terminal (lands in tmux) → `prefix + I`
4. Update NTFY vars in `~/.zshenv`
5. Open Claude Code → paste `post-verify-agent.md` content

### Linux VPS

1. `bash setup-ntfy-server.sh`
2. `bash install-tmux.sh`
3. Open Claude Code → paste `zsh-preflight-agent.md` content
4. Open new terminal (lands in tmux) → `prefix + I`
5. Open Claude Code → paste `post-verify-agent.md` content
