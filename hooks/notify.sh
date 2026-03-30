#!/usr/bin/env bash
# ~/.claude/hooks/notify.sh
# Receives JSON on stdin from Claude Code hooks — sends meaningful content to ntfy

input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // "event"')
session=$(echo "$input" | jq -r '.session_id // "claude"' | cut -c1-8)

case "$event" in
  Notification)
    title=$(echo "$input" | jq -r '.title // "Claude Code"')
    msg=$(echo "$input" | jq -r '.message // "Needs attention"')
    ntfy_title="$title"
    ntfy_msg="[$session] $msg"
    ntype=$(echo "$input" | jq -r '.notification_type // ""')
    case "$ntype" in
      permission_prompt) ntfy_priority="high" ;;
      idle_prompt)       ntfy_priority="default" ;;
      *)                 ntfy_priority="default" ;;
    esac
    ;;
  Stop)
    ntfy_title="Claude Code Stopped"
    raw_msg=$(echo "$input" | jq -r '.last_assistant_message // "Session ended"')
    if [[ ${#raw_msg} -gt 500 ]]; then
      last_msg="${raw_msg:0:500}…"
    else
      last_msg="$raw_msg"
    fi
    ntfy_msg="[$session] $last_msg"
    ntfy_priority="low"
    ;;
  *)
    ntfy_title="Claude Code"
    ntfy_msg="[$session] $event"
    ntfy_priority="default"
    ;;
esac

# Phone notification via self-hosted ntfy — primary channel, works everywhere
NTFY_HEADERS=(-H "Title: $ntfy_title" -H "Priority: $ntfy_priority")
[[ -n "${NTFY_TOKEN:-}" ]] && NTFY_HEADERS+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
curl -s -X POST "${NTFY_URL}/${NTFY_TOPIC}" \
  "${NTFY_HEADERS[@]}" \
  -d "$ntfy_msg" &>/dev/null &

# Desktop notification (macOS) — secondary channel for local sessions
if command -v terminal-notifier &>/dev/null; then
  terminal-notifier -title "$ntfy_title" -message "$ntfy_msg" -sound default
elif command -v osascript &>/dev/null; then
  osascript -e "display notification \"$ntfy_msg\" with title \"$ntfy_title\""
fi
