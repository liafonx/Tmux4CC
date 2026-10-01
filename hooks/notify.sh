#!/usr/bin/env bash
set -euo pipefail
# Never fail the hook: any error just means "no push".
trap 'exit 0' ERR

# ~/.claude/hooks/notify.sh — Claude Code hook → Bark iOS push (https://github.com/Finb/bark)
#
# Pushes only for the MAIN agent (hook input carries .agent_id only inside subagents):
#   PreToolUse AskUserQuestion → "Claude asks"
#   PreToolUse ExitPlanMode    → "Plan ready to approve"
#   Stop                       → "Finished", only when no more work is coming:
#                                no background tasks and no session crons (/loop wakeups)
# Everything else (SubagentStop, Notification, ...) is ignored.
#
# Push layout — a nudge to go back to the computer, not a reading view:
#   title "Claude Code · <host>", subtitle "<session name>", body "<emoji> <State>" only.
#
# Config — environment, else the BARK_* lines of ~/.zsh_secrets
# (Desktop app sessions don't inherit the shell environment):
#   BARK_SERVER       e.g. https://bark.liafonx.net        (required)
#   BARK_DEVICE_KEY   device key(s), comma-separated       (required)
#   BARK_HOST_LABEL   machine name shown in pushes         (default: hostname -s)
#   BARK_ICON         icon URL                             (optional)
#   BARK_SOUND_ASK    sound for questions/plans            (default: minuet)
#   BARK_SOUND_DONE   sound for "Finished"                 (default: Bark default)
#   BARK_DEBUG=1      append raw hook input to $TMPDIR/cc-bark-debug.jsonl
#   BARK_DRY_RUN=1    print the push payload instead of sending it
#
# Usage: notify.sh < hook-input.json
#        notify.sh --test            # send a test push

if [[ -z "${BARK_SERVER:-}" || -z "${BARK_DEVICE_KEY:-}" ]] && [[ -f "$HOME/.zsh_secrets" ]]; then
  # Only the BARK_* lines — the rest of the file may be zsh-specific.
  # eval, not `source <(...)`: macOS /bin/bash 3.2 sources process substitutions as empty.
  eval "$(grep -E '^[[:space:]]*(export[[:space:]]+)?BARK_[A-Z_]+=' "$HOME/.zsh_secrets" || true)"
fi
[[ -n "${BARK_SERVER:-}" && -n "${BARK_DEVICE_KEY:-}" ]] || exit 0
command -v jq &>/dev/null || exit 0

mode="hook"
if [[ "${1:-}" == "--test" ]]; then
  mode="test"
  input=$(jq -n --arg cwd "$PWD" '{hook_event_name: "Test", session_id: "test", cwd: $cwd}')
else
  input=$(cat)
fi

if [[ "${BARK_DEBUG:-}" == "1" ]]; then
  jq -c . <<<"$input" >>"${TMPDIR:-/tmp}/cc-bark-debug.jsonl" || true
fi

host="${BARK_HOST_LABEL:-$(hostname -s)}"

# Project = main repo name (worktrees resolve to their repo), else the cwd's name.
cwd=$(jq -r '.cwd // empty' <<<"$input")
project="Claude Code"
if [[ -n "$cwd" ]]; then
  common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ "$common" == */.git ]]; then
    project=$(basename "${common%/.git}")
  else
    top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
    project=$(basename "${top:-$cwd}")
  fi
fi

# Decide whether to push; prints nothing to skip. The body is just the status:
# a push is a nudge to go back to the computer, not a reading view.
note=$(jq -c \
  --arg sound_ask "${BARK_SOUND_ASK:-minuet}" \
  --arg sound_done "${BARK_SOUND_DONE:-}" '
  if (.agent_id // "") != "" then empty

  elif .hook_event_name == "Test" then
    {body: "🔔 Test", level: "active", sound: ""}

  elif .hook_event_name == "PreToolUse" and .tool_name == "AskUserQuestion" then
    {body: "❓ Question", level: "timeSensitive", sound: $sound_ask}

  elif .hook_event_name == "PreToolUse" and .tool_name == "ExitPlanMode" then
    {body: "📋 Plan ready", level: "timeSensitive", sound: $sound_ask}

  elif .hook_event_name == "Stop" then
    if .stop_hook_active == true
       or ((.background_tasks // []) | length) > 0
       or ((.session_crons // []) | length) > 0
    then empty
    else {body: "✅ Finished", level: "active", sound: $sound_done} end

  else empty end
' <<<"$input")
[[ -n "$note" ]] || exit 0

session=$(jq -r '.session_id // "session"' <<<"$input")

# Session name = the title Claude Code / the Desktop app shows (custom-title in the
# transcript, same as /rename), else the agent name, else the project.
session_name=""
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
if [[ -n "$transcript" && -f "$transcript" ]]; then
  for type in custom-title agent-name; do
    session_name=$(grep -F "\"type\":\"$type\"" "$transcript" | tail -n 1 \
      | jq -r '.customTitle // .agentName // empty' 2>/dev/null || true)
    [[ -n "$session_name" ]] && break
  done
fi
[[ -n "$session_name" ]] || session_name="$project"

payload=$(jq -c -n \
  --argjson n "$note" \
  --arg project "$project" \
  --arg host "$host" \
  --arg session_name "$session_name" \
  --arg keys "$BARK_DEVICE_KEY" \
  --arg id "cc-${session:0:12}" \
  --arg icon "${BARK_ICON:-}" '
  def clip($n): if length > $n then .[0:$n] + "…" else . end;
  ($keys | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $k
  | {title: "Claude Code · \($host)", subtitle: ($session_name | clip(60)),
     body: $n.body,
     level: $n.level, group: $project, id: $id, isArchive: "1"}
  + (if $n.sound != "" then {sound: $n.sound} else {} end)
  + (if $icon != "" then {icon: $icon} else {} end)
  + (if ($k | length) == 1 then {device_key: $k[0]} else {device_keys: $k} end)
')

if [[ "${BARK_DRY_RUN:-}" == "1" ]]; then
  printf '%s\n' "$payload"
  exit 0
fi

resp=$(curl -sS --max-time 10 --retry 2 \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "$payload" "${BARK_SERVER%/}/push" 2>&1 || true)
[[ "$mode" == "test" ]] && printf '%s\n' "$resp"
exit 0
