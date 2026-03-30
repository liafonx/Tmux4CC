# zsh Preflight Agent — tmux4CC

## Purpose

This file is run by Claude Code to autonomously audit and patch zsh configuration files on the current machine. The agent inspects `~/.zshrc`, `~/.zshenv`, and related files, then applies targeted patches to enable three things: tmux auto-start on every interactive shell, correct `TERM` settings inside tmux sessions, and the environment variables required for the Claude Code notification hook (ntfy). All edits are idempotent, non-destructive, and reported back to the user with a structured summary.

## Safety Rules

- Always back up files before editing: `~/.zshrc` → `~/.zshrc.pre-tmux4cc.bak`, `~/.zshenv` → `~/.zshenv.pre-tmux4cc.bak`
- Apply changes idempotently — check before adding (grep for marker text `tmux4cc` first)
- Never remove or comment out existing lines unless explicitly instructed
- Report what changed and what was already correct

---

## Machine Detection

Run the following commands to identify the current machine:

```bash
whoami
uname -s
uname -m
hostname
```

Map the output to a machine profile:

| `whoami` | `uname -s` | `uname -m` | Machine |
|----------|------------|------------|---------|
| `liafo` | `Darwin` | `arm64` | MacBook |
| `liafonx` | `Darwin` | `x86_64` | Mac Mini |
| `liafonx` | `Linux` | `x86_64` | Linux VPS |

---

## **CRITICAL: Insertion Order Rule**

In `~/.zshrc`, blocks must be inserted in this exact order AFTER the p10k instant prompt block:

1. **tmux auto-start block** (FIRST)
2. **TERM guard** (SECOND, immediately after auto-start)

This order is mandatory. The auto-start block uses `exec`, which replaces the shell process with tmux. The TERM guard only reaches execution when the shell is already running inside tmux — so it must follow the auto-start block, never precede it.

---

## Exact Code Blocks to Insert

**tmux auto-start block** — insert into `~/.zshrc`:

```zsh
# ── tmux auto-start (tmux4cc) ────────────────────────────────────────────────
# Prefer the most recently active claude/codex window in same dir, then zsh, else new.
# Includes session_activity for sorting; picks the latest active AI session.
if [[ -z $TMUX && -z $SKIP_TMUX && $- == *i* && -t 0 ]]; then
  match=$(tmux list-windows -a -F "#{session_activity}|#{session_name}:#{window_index}|#{pane_current_path}|#{pane_current_command}" 2>/dev/null \
    | sort -t'|' -k1 -rn \
    | awk -F"|" -v d="$PWD" '
      $3==d && ($4~/^[0-9]+\.[0-9]+\.[0-9]+$/ || $4~/^codex/ || $4=="claude") && !ai {ai=$2}
      $3==d && $4=="zsh" && !zsh {zsh=$2}
      END {if(ai) print ai; else if(zsh) print zsh}')
  if [[ -n "$match" ]]; then
    exec tmux attach-session -t "$match"
  else
    exec tmux new-session -As "${PWD##*/}"
  fi
fi
```

**TERM guard** — insert into `~/.zshrc` immediately after the auto-start block:

```zsh
# ── TERM guard (tmux4cc) ─────────────────────────────────────────────────────
[[ -n $TMUX ]] && export TERM=tmux-256color
```

**cd auto-attach + session rename hook** — insert into `~/.zshrc` after the TERM guard:

```zsh
# ── cd auto-attach to claude/codex + session rename (tmux4cc) ───────────────
# On cd: switch to existing AI window in target dir, and rename session to dir basename.
_tmux4cc_chpwd() {
  [[ -z $TMUX ]] && return
  # Rename current session to the new directory basename
  tmux rename-session "${PWD##*/}" 2>/dev/null
  # Switch to existing AI window in the target dir (across all sessions)
  local cur_sess cur_win match
  cur_sess=$(tmux display-message -p '#{session_name}')
  cur_win=$(tmux display-message -p '#{window_index}')
  match=$(tmux list-windows -a -F '#{session_name}:#{window_index}|#{pane_current_path}|#{pane_current_command}' \
    | awk -F'|' -v d="$PWD" -v cs="$cur_sess" -v cw="$cur_win" \
      '$2==d && ($3~/^[0-9]+\.[0-9]+\.[0-9]+$/ || $3~/^codex/ || $3=="claude") {
        split($1, a, ":"); if (a[1]!=cs || a[2]!=cw) {print $1; exit}
      }')
  [[ -n "$match" ]] && tmux switch-client -t "$match"
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _tmux4cc_chpwd
```

**NTFY placeholders** — append to `~/.zshenv`:

```zsh
# ── ntfy notification vars (tmux4cc) ─────────────────────────────────────────
export NTFY_URL="https://CHANGEME"
export NTFY_TOPIC="CHANGEME"
```

---

## MacBook Checklist (`liafo@*`, Darwin/arm64)

Execute steps in order:

1. **Back up files**: Run `cp ~/.zshrc ~/.zshrc.pre-tmux4cc.bak` and `cp ~/.zshenv ~/.zshenv.pre-tmux4cc.bak`. Note: `~/.zshenv` already exists and contains `source ~/.cargo/env`.

2. **Move PATH block to ~/.zshenv**: Read lines 13–41 of `~/.zshrc` (the `path=(...)` array block). Append those lines to `~/.zshenv`, then remove them from `~/.zshrc`. Also find and move the Go PATH line (`export PATH=$PATH:$(go env GOPATH)/bin` or similar, around line 104) using the same append-then-remove pattern.

3. **Add locale to ~/.zshenv**: Grep `~/.zshenv` for `LANG`. If not present, append:
   ```zsh
   export LANG=en_US.UTF-8
   export LC_ALL=en_US.UTF-8
   ```

4. **Add NTFY placeholders to ~/.zshenv**: Grep `~/.zshenv` for `NTFY_URL`. If not present, append the NTFY block shown above.

5. **Add `tmux` to plugins**: In `~/.zshrc`, find the `plugins=(...)` array. If `tmux` is not already listed, add it. Edit in-place; do not reformat other entries.

6. **Add tmux auto-start block**: Search `~/.zshrc` for the marker `tmux4cc`. If not found, locate the end of the p10k instant prompt block (search for `# End of Powerlevel10k instant prompt` or the closing `fi` of the p10k sourcing guard). Insert the auto-start block immediately after that line.

7. **Add TERM guard**: Search `~/.zshrc` for `TERM guard (tmux4cc)`. If not found, insert the TERM guard immediately after the auto-start block inserted in step 6.

---

## Mac Mini Checklist (`liafonx@Liafonxs-Mac-mini`, Darwin/x86_64)

Execute steps in order:

1. **Back up files**: Run `cp ~/.zshrc ~/.zshrc.pre-tmux4cc.bak`. Note: no `~/.zshenv` exists yet — it will be created in step 2.

2. **Create ~/.zshenv**: Create the file. Find `LANG`/`LC_ALL` export lines in `~/.zshrc` (typically near the bottom) and move them into `~/.zshenv`. Append `typeset -U PATH` at the bottom of the new file.

3. **Move PATH exports to ~/.zshenv**: Find and move the following scattered PATH exports from `~/.zshrc` to `~/.zshenv` (append-then-remove pattern):
   - `/usr/local/opt/curl/bin`
   - `/usr/local/opt/postgresql@16/bin`
   - `$BUN_INSTALL/bin`
   - `~/.local/bin`

   Ensure `typeset -U PATH` is present in `~/.zshenv` after all PATH mutations (deduplicates entries).

4. **Add NTFY placeholders to ~/.zshenv**: Grep `~/.zshenv` for `NTFY_URL`. If not present, append the NTFY block shown above.

5. **Add `tmux` to plugins**: In `~/.zshrc`, find the `plugins=(...)` array. If `tmux` is not already listed, add it.

6. **Add tmux auto-start block**: Search `~/.zshrc` for the marker `tmux4cc`. If not found, locate the end of the p10k instant prompt block and insert the auto-start block immediately after it.

7. **Add TERM guard**: Search `~/.zshrc` for `TERM guard (tmux4cc)`. If not found, insert the TERM guard immediately after the auto-start block.

8. **FLAG (do not modify)**: Warn the user that `CF_Token` appears as a plaintext credential in `~/.zshrc`. Recommend moving it to `~/.secrets` (chmod 600), then sourcing that file from `~/.zshenv`. Do NOT touch the line itself.

Note: Leave `.zprofile` as-is. It correctly contains brew shellenv and pipx PATH — the right location for login shell setup.

---

## Linux VPS Checklist (`liafonx@naranja-nl`, Linux/x86_64)

Execute steps in order:

1. **Back up files**: Run `cp ~/.zshrc ~/.zshrc.pre-tmux4cc.bak`. Note: no `~/.zshenv` or `~/.zprofile` exists — both will be created as needed.

2. **Create ~/.zshenv**: Create the file with the following contents:
   ```zsh
   export LANG=en_US.UTF-8
   export LC_ALL=en_US.UTF-8
   typeset -U PATH
   ```

3. **Add NTFY vars to ~/.zshenv**: This machine IS the ntfy server, so real values are needed rather than placeholders. Ask the user to provide the `NTFY_URL` and `NTFY_TOPIC` values from the `setup-ntfy-server.sh` output, then append them to `~/.zshenv` in the standard NTFY block format.

4. **Add `tmux` to plugins**: In `~/.zshrc`, find the `plugins=(...)` array. If `tmux` is not already listed, add it.

5. **Add tmux auto-start block**: Search `~/.zshrc` for the marker `tmux4cc`. If not found, locate the end of the p10k instant prompt block and insert the auto-start block immediately after it.

6. **Add TERM guard**: Search `~/.zshrc` for `TERM guard (tmux4cc)`. If not found, insert the TERM guard immediately after the auto-start block.

7. **Fix compound quoting breakage in ~/.zshrc**:
   - Find the line `export PATH="$HOME/.local/bin:$PATH` (missing closing `"`). Fix it to:
     ```zsh
     export PATH="$HOME/.local/bin:$PATH"
     ```
   - Find the immediately following line `export CF_Token=...` which has a stray `"` at the end. Fix the quoting so it is syntactically valid.
   - These two broken lines corrupt every export below them in the file — this fix is required for any subsequent changes to take effect.

8. **FLAG (do not modify)**: Warn the user that `NORD_USERNAME`, `NORD_PASSWORD`, and `CF_Token` are plaintext credentials in `~/.zshrc`. Recommend moving all three to `~/.secrets` (chmod 600), then adding `source ~/.secrets` to `~/.zshenv`. Do NOT touch those lines.

---

## Agent Output Format

After completing all steps, print the following summary report, substituting the actual machine name and reflecting which steps were applied versus already correct:

```
═══════════════════════════════════════
  zsh Preflight Summary — <machine>
═══════════════════════════════════════
✓ Backed up: ~/.zshrc → ~/.zshrc.pre-tmux4cc.bak
✓ Backed up: ~/.zshenv → ~/.zshenv.pre-tmux4cc.bak
✓ PATH moved to ~/.zshenv
✓ Locale set in ~/.zshenv
✓ NTFY placeholders added to ~/.zshenv
✓ tmux added to oh-my-zsh plugins
✓ tmux auto-start block added to ~/.zshrc
✓ TERM guard added to ~/.zshrc
⚠ CF_Token is a plaintext credential — move to ~/.secrets

Already correct (no changes):
  - (list items that were already in place)

Next: open a new terminal and verify you land in a tmux session
```
