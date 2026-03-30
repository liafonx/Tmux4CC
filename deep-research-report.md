# Claude Code inside tmux: a durable, multi-device workflow

This guide sets up an opinionated, low-maintenance workflow where **Claude Code** runs persistently inside **tmux**, so you can disconnect and reconnect from any device while keeping the same interactive session alive. It covers local-only, remote-only, and dual-mode usage — all with the same configuration.

The setup is specifically designed for: **macOS arm64**, **Termius** as the terminal client, **zsh + oh-my-zsh (system-level) + powerlevel10k**, and a clean tmux slate. Target session count: 1–6 parallel Claude Code sessions.

Every recommendation is tagged: **[must-have]**, **[optional]**, or **[nice-to-have]**.

---

## Architecture: what you're building and why

```
Termius (local)  ──SSH──►  tmux server (remote or local)
                                │
                    ┌───────────┼───────────┐
                  claude      scratch     monitor
                 (window 1)  (window 2)  (window 3)
```

The core insight: **tmux holds process state; Claude Code holds conversation state**. These are independent persistence layers that complement each other.

1. **tmux server** keeps sessions, windows, pane processes, and scrollback alive across network drops and intentional detaches.
2. **Claude Code** persists conversation state and reversible checkpoints via `claude --continue` / `--resume`, even if you restart the CLI.
3. **Hooks** bridge Claude Code events to your notification system, so you're never staring at a waiting prompt you didn't notice.

### Local vs. remote: same config, different connect command

- **Local**: `tmux new-session -A -s cc` — run directly in your local terminal.
- **Remote**: `ssh my-claude-box` then `tmux new-session -A -s cc`, or put it in your SSH `RemoteCommand`.
- **Switching**: detach with `Ctrl+B d`, reconnect with the same command from any device.

The `-L` flag (`tmux -L claude`) lets you run a dedicated tmux server socket isolated from personal tmux usage — useful when you have an existing tmux setup you don't want to pollute.

---

## Prerequisites and zsh + p10k invariants

### UTF-8 locale [must-have]

Powerlevel10k's glyphs require UTF-8. tmux respects `LC_CTYPE`. On the host running tmux:

```sh
echo $LANG   # should contain UTF-8
```

If it doesn't, either fix it at the system level or start tmux with `tmux -u ...`.

### zsh startup file order [must-have, know this to avoid headaches]

| File | When it runs | What belongs here |
|------|-------------|-------------------|
| `.zshenv` | Every invocation, including scripts | PATH, critical env vars only. No output. |
| `.zshrc` | Interactive shells | oh-my-zsh, p10k, aliases |
| `.zprofile` | Login shells only | Not always loaded in new tmux panes |

tmux creates new panes as interactive, non-login shells — so `.zprofile` may not run. If "works over SSH but not in new tmux panes" happens to you, PATH setup is in the wrong file.

### p10k Instant Prompt [must-have awareness]

Instant Prompt is excellent but strict: anything requiring console input must go **above** the instant prompt preamble in `.zshrc`. Console output during init causes warnings. If you can't fix the ordering, set `POWERLEVEL9K_INSTANT_PROMPT=quiet`.

This is especially visible in tmux because you spawn many fresh zsh shells (panes, popups, resurrected sessions).

---

## Core tmux configuration [must-have]

**Location**: `~/.config/tmux/tmux.conf`

```tmux
# ─── Terminal correctness ────────────────────────────────────────────────────

# tmux requires TERM to be screen/tmux-derived internally.
set -g default-terminal "tmux-256color"

# Termius sends xterm-256color as the outer TERM — declare truecolor for it.
# Add additional patterns if you switch outer terminals.
set -as terminal-features ",xterm-256color:RGB"
set -as terminal-features ",xterm-kitty:RGB"

# ─── Ergonomics ──────────────────────────────────────────────────────────────

# Faster escape handling (useful for vi-mode; remove if Alt/meta keys break).
set -s escape-time 10

# Long scrollback for Claude output and command transcripts.
set -g history-limit 100000

# Mouse support for scroll and copy in long AI outputs.
set -g mouse on

# Pass focus events to applications (helps some TUIs).
set -g focus-events on

# ─── Window naming ───────────────────────────────────────────────────────────

# Prevent tmux from auto-renaming based on active process.
set -wg automatic-rename off
set -wg allow-rename off

# ─── Clipboard ───────────────────────────────────────────────────────────────

# OSC 52: lets tmux set the host clipboard over SSH without X11 forwarding.
# "external" prevents apps inside tmux from setting the clipboard (security).
set -s set-clipboard external
set -as terminal-features ",xterm-256color:clipboard"

# ─── Environment refresh on attach ───────────────────────────────────────────

# Copy these vars into the session when you reattach from another machine.
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AUTH_SOCK SSH_CONNECTION SSH_TTY XAUTHORITY LANG LC_ALL LC_CTYPE"

# ─── Keybindings ─────────────────────────────────────────────────────────────

# Reload config without restarting.
bind r source-file ~/.config/tmux/tmux.conf \; display-message "reloaded"

# Splits that inherit the current pane's path.
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Popup scratch shell: overlay zsh, closes on exit, inherits current path.
bind p display-popup -E -d "#{pane_current_path}" -w 90% -h 60% "zsh"

# ─── Logging ─────────────────────────────────────────────────────────────────

# Toggle pane output logging to file. Run mkdir -p ~/.tmux/logs first.
bind L pipe-pane -o "cat >> ~/.tmux/logs/output.#I-#P.log"
```

### Why these choices

- `default-terminal "tmux-256color"`: tmux requires `screen`, `tmux`, or a derivative as the internal TERM — this is not optional.
- `terminal-features` with `RGB`: this is the current recommended way to declare truecolor support; old `terminal-overrides` with `Tc` still works but `terminal-features` is preferred.
- **Termius note**: Termius reports `xterm-256color` as `$TERM`. That's why `xterm-256color:RGB` is the critical line. Termius supports truecolor and OSC 52 clipboard natively — no special config needed on the Termius side.
- `set-clipboard external`: Security trade-off — with `on`, any app inside tmux can write to your system clipboard; `external` limits that to tmux itself.
- `escape-time 10`: The default (500ms) causes noticeable delay; 10ms is safe for modern systems.

---

## Claude Code integration

### Ctrl+B conflict [must-have fix]

Claude Code uses `Ctrl+B` for `task:background`. tmux uses `Ctrl+B` as its default prefix. Result: pressing `Ctrl+B` once sends it to tmux, not Claude. You must press it twice to send it through.

**Recommended fix**: rebind Claude Code's shortcut, not tmux's prefix. Changing the tmux prefix causes more friction with zsh keybindings (`Ctrl+A` for beginning-of-line, etc.).

Create `~/.claude/keybindings.json`:

```json
{
  "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
  "bindings": [
    {
      "context": "Task",
      "bindings": {
        "meta+b": "task:background"
      }
    }
  ]
}
```

Requires Claude Code v2.1.18+. Changes apply without restart.

### Session hygiene [must-have habits]

- `/clear` — reset context between tasks without restarting the CLI.
- `/rewind` (or `Esc Esc`) — restore prior state; checkpoints persist across sessions.
- `claude --continue` / `--resume` — pick up a session even after restarting the CLI.
- `/rename` — name sessions like branches; makes parallel work trackable.

**Pattern**: one tmux window per task, one Claude session per task (named). Claude handles conversation state; tmux handles UI stability.

---

## Notification system [must-have]

This is the most impactful addition for 1–6 parallel Claude Code sessions. Without notifications, you're either polling windows or missing that Claude is waiting for input.

### How Claude Code hooks work

Claude Code fires hooks on lifecycle events. Relevant ones:

| Hook type | When it fires |
|-----------|--------------|
| `Notification` | Claude wants to notify you (task done, needs input) |
| `Stop` | Claude has finished and stopped |
| `PreToolUse` with `AskUserQuestion` matcher | Claude is about to ask you a question (blocking) |

Hooks are configured in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh"
          }
        ]
      }
    ]
  }
}
```

### notify.sh: dual-channel notification

```bash
#!/usr/bin/env bash
# ~/.claude/hooks/notify.sh
# Receives JSON on stdin from Claude Code hooks

input=$(cat)
session=$(echo "$input" | jq -r '.session_id // "claude"' | cut -c1-8)
event=$(echo "$input" | jq -r '.hook_event_name // "event"')
msg="Claude [$session]: $event"

# Phone notification via self-hosted ntfy — primary channel, works everywhere
# NTFY_URL: base URL of your self-hosted ntfy instance (set in ~/.zshenv)
# NTFY_TOPIC: your notification topic (set in ~/.zshenv)
curl -s -X POST "${NTFY_URL}/${NTFY_TOPIC}" \
  -H "Title: Claude Code" \
  -d "$msg" &>/dev/null &

# Desktop notification (macOS) — secondary channel for local sessions
if command -v terminal-notifier &>/dev/null; then
  terminal-notifier -title "Claude Code" -message "$msg" -sound default
elif command -v osascript &>/dev/null; then
  osascript -e "display notification \"$msg\" with title \"Claude Code\""
fi
```

Make it executable: `chmod +x ~/.claude/hooks/notify.sh`

### Setup

**ntfy (self-hosted, mandatory)**:
1. Deploy ntfy on your VPS — it's a single Go binary: `apt install ntfy` or the Docker image.
2. Install the ntfy app on your phone and point it to your VPS URL.
3. Subscribe to a topic (make it unique: `claude-yourname-abc123`).
4. Set these in `~/.zshenv` so they're available in all tmux panes and scripts:
   ```sh
   export NTFY_URL="https://ntfy.yourdomain.com"   # your VPS, not ntfy.sh
   export NTFY_TOPIC="claude-yourname-abc123"
   ```

**terminal-notifier** (macOS desktop notifications, secondary):
```sh
brew install terminal-notifier
```

### tmux monitor-silence: task-done detection [nice-to-have]

For a tmux-native approach without hooks: `monitor-silence N` highlights a window in the status bar when it's been silent for N seconds. Useful as a "Claude finished running something" signal.

```tmux
# In tmux.conf or run interactively:
setw monitor-silence 30
```

This is complementary to hooks, not a replacement — hooks fire on Claude Code events, while monitor-silence catches general terminal silence.

---

## Popup and scratch-command workflows

### Popup scratch shell [must-have]

Bound to `prefix + p` in the config above. Opens an overlay zsh shell rooted in the current pane's directory. Closes automatically on exit.

**Important**: panes are not updated while a popup is visible. Claude keeps running, but you won't see output until you close the popup. Acceptable for quick commands; use a split if you need continuous visibility.

### Side-by-side split pane [optional]

Use `prefix + |` to split a side pane for persistent watchers (tests, `tail -f`, `git status` loops). tmux zoom (`prefix + z`) lets you toggle focus between "everything visible" and "just Claude fullscreen."

---

## SSH config (remote mode)

Keep it minimal — only what prevents flaky connections:

```sshconfig
Host my-claude-box
  HostName your.server.example
  User youruser
  RequestTTY force
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPersist 10m
  ControlPath ~/.ssh/cm-%C
```

- `RequestTTY force`: ensures an interactive TTY, which tmux requires.
- `ControlMaster` + `ControlPersist`: multiplexes SSH connections so reconnects are fast (reuses the existing TCP connection).
- `ServerAliveInterval`: detects dead connections before they silently stall.

**One-liner to connect and attach**:
```sh
ssh my-claude-box -t 'tmux new-session -A -s cc'
```

Or put it in a shell alias: `alias cc='ssh my-claude-box -t "tmux new-session -A -s cc"'`

### Mosh [nice-to-have, for unstable networks]

If you frequently switch networks or work on mobile connections, Mosh handles roaming and intermittent connectivity better than SSH. Use it *in addition to* tmux, not instead — Mosh improves the transport; tmux preserves process state.

---

## Tmux plugins and companion tools

### Plugin manager: TPM [optional, prerequisite for plugins]

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Add to the **bottom** of `tmux.conf`:
```tmux
run '~/.tmux/plugins/tpm/tpm'
```

Install plugins: `prefix + I`. Update: `prefix + U`.

### tmux-resurrect [optional, strongly recommended for remote machines]

Saves and restores sessions, windows, panes, working directories, and layouts across tmux server restarts (e.g., after a reboot).

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
```

- Save: `prefix + Ctrl-s`
- Restore: `prefix + Ctrl-r`

Particularly valuable on remote machines where reboots lose your layout.

### tmux-continuum [nice-to-have]

Adds periodic auto-save and auto-restore on tmux server start. Requires the tmux status line to be active (it uses status-right hooks internally).

```tmux
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'  # minutes
```

Only add this if you accept "save every N minutes" behavior and keep the status line on.

### tmux-thumbs [optional, high-value for AI output]

Fast text selection from terminal output using a hint-based picker (similar to vim-easymotion for terminal content). Particularly useful for grabbing file paths, error codes, and commit hashes from Claude's output without mouse selection.

```tmux
set -g @plugin 'fcsonline/tmux-thumbs'
```

Trigger: `prefix + Space` (configurable). Type the hint letter to copy the matched text.

### tmux-fuzzback [optional, high-value for long sessions]

Fuzzy search through tmux scrollback history. Find that thing Claude said three pages ago without scrolling manually.

```tmux
set -g @plugin 'roosta/tmux-fuzzback'
```

Requires `fzf`. Trigger: `prefix + ?`

---

## Parallel agent workflows [optional for 1 session, essential for 3+]

### Git worktrees + tmux windows [must-have for parallel work]

Running parallel Claude tasks in the same working directory causes conflicts. The solution:

```sh
# Create a worktree for each task
git worktree add ../project-feature-auth feature/auth
git worktree add ../project-bugfix-login bugfix/login

# Each gets its own tmux window
tmux new-window -n "auth" -c "../project-feature-auth"
tmux new-window -n "login" -c "../project-bugfix-login"
```

Pattern: one git worktree → one tmux window → one named Claude session. Claude Code's status line schema includes `worktree.*` fields when using `--worktree`, so you can display which worktree is active.

### claude-squad [nice-to-have for 4+ parallel agents]

A community tool that manages multiple Claude Code agent instances in separate tmux windows/worktrees with a dashboard view. Built on tmux; adds tooling overhead but reduces manual orchestration.

Worth evaluating if you find yourself managing 4+ parallel Claude sessions regularly. Otherwise, the manual worktree + window pattern above is simpler.

### monitor-silence for task completion [optional]

Already covered in the notification section. As a workflow pattern: set `monitor-silence 30` on windows running long Claude tasks. The window title highlights in the tmux status bar when the session goes quiet — a lightweight "done" signal that requires zero external tooling.

---

## Logging and transcripts

### Pane logging [optional]

Toggle with `prefix + L` (bound in the config above):

```sh
mkdir -p ~/.tmux/logs
```

Logs per-pane output to `~/.tmux/logs/output.<window>-<pane>.log`.

### Claude transcript path [must-have to know about]

Claude Code's status line JSON includes `transcript_path` — a stable pointer to the conversation transcript file. Use it for naming log files or building audit trails:

```sh
# Example: symlink today's transcript to a human-readable name
TRANSCRIPT=$(claude-statusline-output | jq -r '.transcript_path')
ln -sf "$TRANSCRIPT" ~/claude-logs/current-session.jsonl
```

---

## oh-my-zsh tmux plugin

The oh-my-zsh `tmux` plugin provides aliases (`to` for `tmux new-session -A -s`) and exposes configuration variables including `ZSH_TMUX_FIXTERM`.

**Recommendation**: enable it only for the aliases. Add `tmux` to your `plugins` array in `.zshrc`. Two cautions:

1. **Do not set `ZSH_TMUX_AUTOSTART=true`**. It surprises you in scripts and nested shells.
2. **Let your tmux config own terminal correctness**, not `ZSH_TMUX_FIXTERM`. You want one canonical source for TERM/truecolor decisions.

---

## Auto-starting Claude Code in tmux [must-have]

Every new terminal should land inside tmux automatically. This ensures Claude Code always runs in a persistent session — no naked shells, no accidentally disconnected processes.

### The pattern

Add this block to `~/.zshrc`, immediately after the p10k instant prompt preamble (after line 7 or wherever the `# End of Powerlevel10k instant prompt` comment is):

```zsh
# Auto-attach to (or create) the main tmux session.
# Bypass with: SKIP_TMUX=1 zsh  or  zsh --norc
if [[ -z $TMUX && -z $SKIP_TMUX && $- == *i* ]]; then
  exec tmux new-session -A -s cc
fi
```

**Why `exec`**: `exec` replaces the current shell process with tmux instead of forking a child. Without `exec`, the outer zsh stays alive as a zombie after tmux exits. With `exec`, the shell is gone and tmux owns the TTY cleanly.

**Why `-A -s cc`**: `-A` means "attach if the session already exists, create it if not." `-s cc` is the session name. This makes the behavior idempotent — running it from two terminals both land in the same session (or you can detach and the other stays alive).

**Why after the instant prompt block**: p10k's instant prompt initializes early and issues console output. The auto-start `exec` must come after that block, otherwise p10k throws a warning on every new pane.

**Why `[[ $- == *i* ]]`**: guards against firing in non-interactive shells (scripts, SSH commands, cron). The `-z $TMUX` guard prevents recursion inside an already-running tmux session.

### Bypassing it temporarily

```sh
# Start a plain shell without tmux (e.g. for a script that needs a clean env):
SKIP_TMUX=1 zsh

# Or bypass all of .zshrc entirely:
zsh --norc
```

### Where Claude Code fits

Once you're inside tmux, Claude Code runs normally. The key benefit: if your terminal app crashes, your network drops, or you switch devices, `tmux new-session -A -s cc` from any terminal instantly returns you to the same Claude session mid-thought.

---

## zsh + oh-my-zsh + p10k: adjustments for tmux [must-have]

A fresh zsh config works fine for interactive use but has gaps that surface in tmux. Here are the exact changes required, in order.

### 1. Move PATH to `~/.zshenv`

PATH defined only in `~/.zshrc` is invisible to non-interactive tmux panes, scripts launched from tmux, and Claude Code's tool execution subshells. Move it to `~/.zshenv` where it loads for every zsh invocation:

```zsh
# ~/.zshenv  — add these (or move from ~/.zshrc)
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
# ... all other PATH entries ...
export PATH="$(go env GOPATH)/bin:$PATH"

# Prevent duplicates (zsh built-in)
typeset -U PATH
```

Remove the duplicated PATH block from `~/.zshrc` after moving it.

### 2. Set locale in `~/.zshenv`

Without explicit locale, p10k glyphs render as question marks or boxes in some tmux panes. Set it in `.zshenv` so it's present for every shell, including scripts:

```zsh
# ~/.zshenv
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

### 3. Set notification env vars in `~/.zshenv`

Required by `notify.sh` (see notification section). They must be in `.zshenv` so they're present in Claude Code's hook subshells:

```zsh
# ~/.zshenv
export NTFY_URL="https://ntfy.yourdomain.com"
export NTFY_TOPIC="claude-yourname-abc123"
```

### 4. Add `tmux` plugin to oh-my-zsh

In `~/.zshrc`, add `tmux` to the plugins array. This gives you `to`, `tad`, `ts` and other convenience aliases:

```zsh
plugins=(
  git
  tmux        # ← add this
  # ... your other plugins ...
)
```

Do **not** set `ZSH_TMUX_AUTOSTART=true` or `ZSH_TMUX_FIXTERM=true` — those conflict with the auto-start guard above and with tmux's own TERM config.

### 5. Set TERM guard inside tmux

Ensure `$TERM` is correct when inside a tmux session. Add this after the p10k instant prompt block in `~/.zshrc` (after the auto-start block):

```zsh
# ~/.zshrc — after instant prompt block
[[ -n $TMUX ]] && export TERM=tmux-256color
```

This is a belt-and-suspenders guard: tmux's `default-terminal "tmux-256color"` sets it inside tmux, but some tools reset `$TERM` during shell init. This line ensures it stays correct throughout your session.

### 6. Auto-start block placement

The auto-start block (section above) must appear **after** the p10k instant prompt preamble and **before** the rest of `.zshrc`. The correct order in `~/.zshrc`:

```zsh
# 1. p10k instant prompt (already at top — do not move)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# 2. tmux auto-start (must be before oh-my-zsh source)
if [[ -z $TMUX && -z $SKIP_TMUX && $- == *i* ]]; then
  exec tmux new-session -A -s cc
fi

# 3. TERM guard for inside-tmux context
[[ -n $TMUX ]] && export TERM=tmux-256color

# 4. oh-my-zsh source + plugins + rest of config
export ZSH="$HOME/.oh-my-zsh"
# ...
```

### Summary of changes

| File | Change |
|------|--------|
| `~/.zshenv` | Add `LANG`/`LC_ALL`, move PATH blocks here, add `NTFY_URL`/`NTFY_TOPIC` |
| `~/.zshrc` | Remove PATH blocks (now in `.zshenv`), add tmux auto-start, add TERM guard, add `tmux` to plugins |

---

## Troubleshooting

### p10k prompt looks wrong (colors, glyphs, spacing)

1. **Locale**: `echo $LC_CTYPE` must include UTF-8. Fix or start tmux with `-u`.
2. **TERM/truecolor**: `default-terminal` must be `tmux-256color`. Add your outer terminal's TERM to `terminal-features` with `:RGB`.
3. **Termius**: Termius supports truecolor natively — if colors are wrong inside tmux on Termius, the `xterm-256color:RGB` line in `terminal-features` is what fixes it.
4. **p10k instant prompt warnings**: move offending initialization above the p10k preamble or set `POWERLEVEL9K_INSTANT_PROMPT=quiet`.

### Claude Code shortcut doesn't work (Ctrl+B)

Expected behavior when tmux prefix is `Ctrl+B`. Fix: rebind `task:background` to `meta+b` in `~/.claude/keybindings.json` as shown above.

### Clipboard copy from remote doesn't paste locally

Check three things:
1. `set-clipboard` is `external` or `on` (not `off`).
2. `xterm-256color:clipboard` is in `terminal-features`.
3. Termius has clipboard access enabled (it supports OSC 52 by default).

If still broken: `tmux kill-server` and restart — clipboard config changes sometimes require a full restart.

### Reattached from another device, environment feels stale

That's what `update-environment` in the config handles. If a specific var is stale, add it to the list. Common additions: `ANTHROPIC_API_KEY` (if set per-session), `DISPLAY`.

### Popup blocks Claude output updates

Known tmux behavior: panes don't update while a popup is open. Claude is still running — you just can't see updates. Close the popup to see the latest output. If you need live visibility, use a split pane instead.

---

## Implementation notes for setup script agent

This section describes what a setup script needs to do, in order.

### Step 1: Install prerequisites
- `brew install tmux` (tmux itself — currently not installed)
- `brew install terminal-notifier` (desktop notifications — secondary channel)
- `brew install jq` (JSON parsing for hooks)
- `brew install fzf` (required by tmux-fuzzback if used)
- Optional: `brew install mosh`

### Step 2: Create directory structure
```
~/.config/tmux/
~/.tmux/logs/
~/.tmux/plugins/
~/.claude/hooks/
```

### Step 3: Write config files
- `~/.config/tmux/tmux.conf` — the core config from this document
- `~/.claude/hooks/notify.sh` — notification hook (make executable)
- `~/.claude/settings.json` — add hooks config (merge with existing if present)
- `~/.claude/keybindings.json` — Ctrl+B fix
- `~/.ssh/config` — add `my-claude-box` stanza if using remote

### Step 4: Apply zsh changes
Modify `~/.zshenv`:
- Add `export LANG=en_US.UTF-8` and `export LC_ALL=en_US.UTF-8`
- Move all PATH blocks from `~/.zshrc` here (including `$(go env GOPATH)/bin`)
- Add `export NTFY_URL="https://ntfy.yourdomain.com"` (your self-hosted VPS)
- Add `export NTFY_TOPIC="claude-yourname-abc123"`

Modify `~/.zshrc` (after the p10k instant prompt block):
- Remove PATH blocks (now in `.zshenv`)
- Add tmux auto-start guard: `[[ -z $TMUX && -z $SKIP_TMUX && $- == *i* ]] && exec tmux new-session -A -s cc`
- Add TERM guard: `[[ -n $TMUX ]] && export TERM=tmux-256color`
- Add `tmux` to the oh-my-zsh plugins array (no `ZSH_TMUX_AUTOSTART` or `ZSH_TMUX_FIXTERM`)

### Step 5: Install TPM and plugins (if plugins desired)
```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# Then start tmux and press prefix + I to install plugins
```

### Step 6: Verify
- Open a new terminal — it should auto-attach to the `cc` tmux session
- Check `$TERM` inside tmux (`echo $TERM` should show `tmux-256color`)
- Verify truecolor: `curl -s https://raw.githubusercontent.com/robertknight/konsole/master/tests/color-spaces.pl | perl`
- Confirm p10k renders without warnings
- Trigger a Claude hook event and verify your phone receives the ntfy notification

### Decisions the script must make (ask the user or use defaults)
- Use separate `tmux -L claude` socket? (default: no, simpler)
- Include tmux-resurrect? (default: yes for remote, no for local-only)
- ntfy self-hosted URL and topic name? (mandatory — phone notifications are required)
- Remote host details for SSH config? (optional, skip if local-only)

---

## Quick reference: the three things that matter most

If you implement only three things, make them:

1. **Session persistence**: `tmux new-session -A -s cc` with a stable session name
2. **Terminal correctness**: `default-terminal "tmux-256color"` + `terminal-features` with `xterm-256color:RGB`
3. **Ctrl+B fix**: rebind `task:background` to `meta+b` in `~/.claude/keybindings.json`

Everything else is an upgrade on top of these three.
