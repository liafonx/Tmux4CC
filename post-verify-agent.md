# Post-Install Verification Agent — tmux4CC

## Purpose

This agent is run after all installation steps are complete. It checks each component of the tmux4CC setup and produces a pass/fail summary table. It does NOT attempt to fix anything — report only.

---

## Step 1: Machine Detection

Run the following command and capture output:

```bash
whoami && uname -s && uname -m && hostname
```

Use the output to identify the machine:

| Machine | whoami | uname -s | uname -m | hostname pattern |
|---------|--------|----------|----------|-----------------|
| MacBook | `liafo` | `Darwin` | `arm64` | any |
| Mac Mini | `liafonx` | `Darwin` | `x86_64` | any |
| Linux VPS (naranja-nl) | `liafonx` | `Linux` | `x86_64` | any |

Record the identified machine label (e.g., "MacBook", "Mac Mini", "Linux VPS") — use it in the output header.

---

## Step 2: Universal Checks (All Machines)

Run each check below. Capture the raw output and evaluate the pass condition. Record pass or fail and a brief detail string.

| # | Check | Command | Pass Condition |
|---|-------|---------|---------------|
| 1 | tmux installed | `tmux -V` | Exits 0, output shows a version string |
| 2 | tmux.conf parseable | `tmux -L verify-test source-file ~/.config/tmux/tmux.conf 2>&1; tmux -L verify-test kill-server 2>/dev/null \|\| true` | No error output (empty stdout/stderr) |
| 3 | TPM cloned | `test -d ~/.tmux/plugins/tpm && echo pass` | Output is `pass` |
| 4 | TPM plugins installed | `ls ~/.tmux/plugins/` | Directory listing includes `tmux-resurrect`, `tmux-continuum`, `tmux-thumbs`, and `tmux-fuzzback` |
| 5 | notify.sh exists + executable | `test -x ~/.claude/hooks/notify.sh && echo pass` | Output is `pass` |
| 6 | settings.json Notification hook | `jq -r '.hooks.Notification[0].hooks[0].command' ~/.claude/settings.json` | Output is `~/.claude/hooks/notify.sh` |
| 7 | settings.json Stop hook | `jq -r '.hooks.Stop[0].hooks[0].command' ~/.claude/settings.json` | Output is `~/.claude/hooks/notify.sh` |
| 8 | keybindings.json meta+b | `jq -r '.bindings[0].bindings["meta+b"]' ~/.claude/keybindings.json` | Output is `task:background` |
| 9 | TERM guard in .zshrc | `grep -c 'TERM=tmux-256color' ~/.zshrc` | Count is >= 1 |
| 10 | tmux in plugins | `grep -c 'tmux' ~/.zshrc` | Count is >= 1 (confirms tmux appears in plugins array) |
| 11 | Locale in .zshenv | `grep -c 'LC_ALL' ~/.zshenv` | Count is >= 1 |
| 12 | Auto-start block in .zshrc | `grep -c 'tmux4cc' ~/.zshrc` | Count is >= 2 (both blocks carry the marker comment) |
| 13 | PATH in non-interactive shell | `zsh -c 'echo $PATH'` | Output is non-empty and contains expected directories |
| 14 | tmux session lifecycle | `tmux new-session -d -s verify-test && tmux kill-session -t verify-test && echo pass` | Output is `pass` |
| 15 | Notification smoke test | `curl -sf -X POST "$NTFY_URL/$NTFY_TOPIC" -d "tmux4cc verify test" -o /dev/null -w "%{http_code}"` | HTTP status code is `200` |

---

## Step 3: Platform-Specific Checks

### Linux Only (liafonx on naranja-nl)

Run these additional checks when the machine is identified as the Linux VPS:

| # | Check | Command | Pass Condition |
|---|-------|---------|---------------|
| 16 | ntfy service active | `systemctl is-active ntfy` | Output is `active` |
| 17 | ntfy health endpoint | `curl -sf http://localhost:${NTFY_PORT:-80}/v1/health` | Exits 0 (HTTP 200) |
| 18 | ntfy topic POST | `curl -sf -X POST "http://localhost:${NTFY_PORT:-80}/$NTFY_TOPIC" -d "verify" -o /dev/null -w "%{http_code}"` | HTTP status code is `200` |

### macOS Only (MacBook + Mac Mini)

Run these additional checks when the machine is identified as MacBook or Mac Mini:

| # | Check | Command | Pass Condition |
|---|-------|---------|---------------|
| 16 | ntfy server reachable | `curl -sf "$NTFY_URL/$NTFY_TOPIC" -o /dev/null -w "%{http_code}"` | HTTP status code is `200` (or at minimum not `000`) |
| 17 | terminal-notifier installed | `command -v terminal-notifier && echo pass` | Output contains `pass` |

---

## Step 4: Output Format

After running all applicable checks, produce a summary in the following format. Replace `<machine>` with the detected machine label and `<date>` with the current date.

```
═══════════════════════════════════════════════
  Post-Install Verification — <machine>
  Date: <date>
═══════════════════════════════════════════════

│ #  │ Check                          │ Status │ Detail                          │
│────│────────────────────────────────│────────│─────────────────────────────────│
│  1 │ tmux installed                 │  PASS  │ tmux 3.4                        │
│  2 │ tmux.conf parseable            │  PASS  │ no errors                       │
│  3 │ TPM cloned                     │  PASS  │                                 │
│  4 │ TPM plugins installed          │  FAIL  │ Missing: tmux-thumbs            │
│  5 │ notify.sh exists + executable  │  PASS  │                                 │
│  6 │ settings.json Notification hook│  PASS  │ ~/.claude/hooks/notify.sh       │
│  7 │ settings.json Stop hook        │  PASS  │ ~/.claude/hooks/notify.sh       │
│  8 │ keybindings.json meta+b        │  PASS  │ task:background                 │
│  9 │ TERM guard in .zshrc           │  PASS  │ count: 1                        │
│ 10 │ tmux in plugins                │  PASS  │ count: 2                        │
│ 11 │ Locale in .zshenv              │  PASS  │ count: 1                        │
│ 12 │ Auto-start block in .zshrc     │  PASS  │ count: 2                        │
│ 13 │ PATH in non-interactive shell  │  PASS  │ /usr/local/bin:/usr/bin:...     │
│ 14 │ tmux session lifecycle         │  PASS  │                                 │
│ 15 │ Notification smoke test        │  FAIL  │ HTTP 000 — connection refused   │
│ 16 │ ntfy server reachable          │  PASS  │ HTTP 200                        │
│ 17 │ terminal-notifier installed    │  PASS  │ /opt/homebrew/bin/terminal-... │

Overall: 15/17 checks passed

Failures and suggested fixes:
  4. TPM plugins not installed → Open tmux and press prefix + I to install
  15. Notification smoke test failed → Check NTFY_URL and NTFY_TOPIC are set in ~/.zshenv and the ntfy server is reachable
```

---

## Step 5: Failure Fix Hints

For every failing check, append it to the "Failures and suggested fixes" section using the hints below. Do not attempt any fixes — only report.

| Failing Check | Suggested Fix |
|---------------|--------------|
| 4 — TPM plugins not installed | Open tmux and press prefix + I to install |
| 5 — notify.sh not found or not executable | Re-run install-tmux.sh |
| 6 — settings.json Notification hook missing | Re-run install-tmux.sh |
| 7 — settings.json Stop hook missing | Re-run install-tmux.sh |
| 8 — keybindings.json missing meta+b | Re-run install-tmux.sh |
| 9 — TERM guard not in .zshrc | Re-run zsh-preflight-agent.md with Claude Code |
| 12 — Auto-start block not in .zshrc | Re-run zsh-preflight-agent.md with Claude Code |
| 15 — Notification smoke test failed | Check NTFY_URL and NTFY_TOPIC are set in ~/.zshenv and the ntfy server is reachable |
| 16 (Linux) — ntfy service not active | Run: sudo systemctl start ntfy |
| 17 (Linux) — ntfy health failed | Check ntfy config at /etc/ntfy/server.yml and run: sudo systemctl status ntfy |

---

## Agent Constraints

- Do NOT modify any files, configuration, or system state.
- Do NOT attempt to fix any failing check.
- Do NOT skip checks that produce errors — record the error output as the detail and mark the check as FAIL.
- If a command is not applicable to the detected machine, mark it as SKIP and omit it from the pass/fail count.
- If `jq` is not available, mark checks 6, 7, and 8 as SKIP and note "jq not installed" in the detail.
- If environment variables `NTFY_URL` or `NTFY_TOPIC` are unset, mark check 15 as FAIL with detail "NTFY_URL or NTFY_TOPIC not set in environment".
