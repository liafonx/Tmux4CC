#!/usr/bin/env bash
set -euo pipefail
# Never fail the hook: any error just means "no push".
trap 'exit 0' ERR

# ~/.claude/hooks/notify.sh — Claude Code hook → Bark iOS push (https://github.com/Finb/bark)
#
# Sends only through bark-hub (https://bark.liafonx.net/v1/notify, bark-hub repo).
# Missing or unusable hub configuration means no push.
#
# Pushes only for the MAIN agent (hook input carries .agent_id only inside subagents):
#   PreToolUse AskUserQuestion → "Claude asks"
#   PreToolUse ExitPlanMode    → "Plan ready to approve"
#   Notification permission_prompt → "Needs approval": Claude Code sends it only after
#                                a permission prompt has waited ~6 s unanswered, so
#                                approving at the keyboard doesn't buzz the phone.
#                                Subagent prompts count too (they block the work).
#   Stop                       → "Finished", only when no more work is coming:
#                                no background tasks and no session crons (/loop wakeups),
#                                and never for a scheduled-task (routine) session: its first
#                                user message is the app's <scheduled-task name=...> wrapper
#                                (after any leading <system-reminder> blocks)
# Everything else (SubagentStop, other Notification types, ...) is ignored.
#
# Push layout — a nudge to go back to the computer, not a reading view:
#   title "Claude Code · <host>", subtitle "<session name>", body "<emoji> <State>" only.
#
# Config — environment, else hub and notification-option lines of ~/.zsh_secrets
# (Desktop app sessions don't inherit the shell environment):
#   BARK_HUB_URL          e.g. https://bark.liafonx.net    (both of these required;
#   BARK_HUB_TOKEN_CLAUDE token for source "claude"         BARK_HUB_TOKEN is accepted if the
#                                                           per-source one is unset)
#   BARK_HOST_LABEL   machine name shown in pushes         (default: hostname -s)
#   BARK_SOUND_ASK    sound for questions/plans            (default: minuet)
#   BARK_SOUND_DONE   sound for "Finished"                 (default: Bark default)
#   BARK_DEBUG=1      append raw hook input to $TMPDIR/cc-bark-debug.jsonl
#   BARK_DRY_RUN=1    print the push payload instead of sending it (never the token)
#
# Usage: notify.sh < hook-input.json
#        notify.sh --test            # send a test push

if [[ -z "${BARK_HUB_URL:-}" || -z "${BARK_HUB_TOKEN_CLAUDE:-${BARK_HUB_TOKEN:-}}" ]] \
   && [[ -f "$HOME/.zsh_secrets" ]]; then
  # Only hub credentials and notification options; the rest may be zsh-specific.
  # eval, not `source <(...)`: macOS /bin/bash 3.2 sources process substitutions as empty.
  eval "$(grep -E '^[[:space:]]*(export[[:space:]]+)?BARK_(HUB_[A-Z_]+|HOST_LABEL|SOUND_[A-Z_]+|DEBUG|DRY_RUN)=' "$HOME/.zsh_secrets" || true)"
fi

# Both the URL and a token curl's config can carry must resolve.
hub_token="${BARK_HUB_TOKEN_CLAUDE:-${BARK_HUB_TOKEN:-}}"
if [[ -z "${BARK_HUB_URL:-}" || -z "$hub_token" || "$hub_token" == *[!A-Za-z0-9._~+/=-]* ]]; then
  [[ "${1:-}" == "--test" ]] && printf '%s\n' 'bark-hub is not configured: set BARK_HUB_URL and BARK_HUB_TOKEN_CLAUDE (or BARK_HUB_TOKEN) with a usable token'
  exit 0
fi
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

  # "Claude needs your permission to use <tool>". Questions and plans also go through
  # the permission path; they already pushed ❓ / 📋 above, so skip them here.
  elif .hook_event_name == "Notification" and .notification_type == "permission_prompt" then
    if (.message // "") | test("Ask ?User ?Question|Exit ?Plan ?Mode"; "i") then empty
    else {body: "🔐 Needs approval", level: "timeSensitive", sound: $sound_ask} end

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
transcript=$(jq -r '.transcript_path // empty' <<<"$input")

# Scheduled-task (routine) sessions send no "Finished" push; their questions, plans and
# approvals still do. Only the FIRST user record of the transcript counts (within its first 50
# lines), so a later quote of the marker does not match: its text, after any leading
# <system-reminder> blocks (the app adds one in scratch workspaces), must start with the app's
# own <scheduled-task name= wrapper. A missing/unreadable transcript means "not scheduled".
if [[ "$(jq -r '.hook_event_name // empty' <<<"$input")" == "Stop" \
      && -n "$transcript" && -r "$transcript" ]]; then
  scheduled=$(head -n 50 -- "$transcript" 2>/dev/null | jq -Rrn '
    first(inputs | fromjson? | select(type == "object" and .type == "user"))
    | (.message.content // "")
    | (if type == "array" then map(select(type == "object" and .type == "text") | .text // "") | join("")
       elif type == "string" then . else "" end)
    | sub("\\A\\s*<system-reminder>[\\s\\S]*?</system-reminder>\\s*"; "")
    | sub("\\A\\s*<system-reminder>[\\s\\S]*?</system-reminder>\\s*"; "")
    | sub("\\A\\s*<system-reminder>[\\s\\S]*?</system-reminder>\\s*"; "")
    | test("\\A\\s*<scheduled-task name=")' 2>/dev/null || true)
  [[ "$scheduled" == "true" ]] && exit 0
fi

# Session name = the title Claude Code / the Desktop app shows (custom-title in the
# transcript, same as /rename), else the agent name, else the project.
session_name=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  for type in custom-title agent-name; do
    session_name=$(grep -F "\"type\":\"$type\"" "$transcript" | tail -n 1 \
      | jq -r '.customTitle // .agentName // empty' 2>/dev/null || true)
    [[ -n "$session_name" ]] && break
  done
fi
[[ -n "$session_name" ]] || session_name="$project"

# bark-hub: it adds the icon and the device keys and prefixes the thread with the source.
# An empty sound is left out (the Bark default).
payload=$(jq -c -n \
  --argjson n "$note" \
  --arg project "$project" \
  --arg host "$host" \
  --arg session_name "$session_name" \
  --arg thread "cc-${session:0:12}" '
  def clip($n): if length > $n then .[0:$n] + "…" else . end;
  {title: "Claude Code · \($host)", subtitle: ($session_name | clip(60)),
   body: $n.body,
   level: $n.level, group: $project, thread: $thread, is_archive: true}
  + (if $n.sound != "" then {sound: $n.sound} else {} end)
')

if [[ "${BARK_DRY_RUN:-}" == "1" ]]; then
  printf '%s\n' "$payload"
  exit 0
fi

# The token goes to curl on stdin (-K -), never on the command line. --retry is safe: the
# payload always carries a thread, so a repeated push replaces itself.
extra=()
[[ "$mode" == "test" ]] && extra=(-w '\nhttp %{http_code}')
resp=$(printf 'header = "Authorization: Bearer %s"\n' "$hub_token" | curl -sS -K - \
  --max-time 5 --retry 2 ${extra[@]+"${extra[@]}"} \
  -H 'Content-Type: application/json; charset=utf-8' \
  --data-binary "$payload" "${BARK_HUB_URL%/}/v1/notify" 2>&1 || true)
[[ "$mode" == "test" ]] && printf '%s\n' "$resp"
exit 0
