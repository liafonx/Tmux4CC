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
# Push layout (kept short — it's a nudge to go back to the computer):
#   title "Claude Code · <host>", subtitle "<session name>",
#   body  "<emoji> <State>" + one line of context (≤ ~120 columns ≈ 3 phone lines).
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

# Decide whether to push and build the message; prints nothing to skip.
# The push is a nudge to go back to the computer, not a reading view: body =
# "<emoji> <State>" line + one short plain-text line (Bark doesn't render markdown).
note=$(jq -c \
  --arg host "$host" \
  --arg sound_ask "${BARK_SOUND_ASK:-minuet}" \
  --arg sound_done "${BARK_SOUND_DONE:-}" '
  # Markdown text → its prose lines (fenced code, table separators and rules dropped).
  def prose_lines:
    gsub("\r"; "") | split("\n")
    | reduce .[] as $l ({out: [], code: false};
        if ($l | test("^\\s*(```|~~~)")) then .code |= not
        elif .code then .
        else .out += [$l] end)
    | .out | map(select(test("\\S") and (test("^\\s*\\|?[\\s:|-]*-[\\s:|-]*\\|?\\s*$") | not)));
  def inline:
    sub("^\\s*#+\\s*"; "")                                              # heading
    | sub("^\\s*>\\s?"; "")                                             # blockquote
    | sub("^\\s*([-*+]|\\d+[.)])\\s+"; "")                              # list marker
    | gsub("\\[(?<t>[^\\]]+)\\]\\([^)]*\\)"; "\(.t)")                   # [text](url) → text
    | gsub("\\*\\*|~~|`"; "")                                         # bold, strike, code
    | gsub("\\*(?<t>[^*\\s][^*]*)\\*"; "\(.t)")                         # *italic*
    | gsub("\\s*\\|\\s*"; " ") | gsub("^\\s+|\\s+$"; "");               # table cells, trim
  # Join lines into one; " · " where a line has no closing punctuation (e.g. list items).
  def join_lines:
    reduce .[] as $l (""; if . == "" then $l
                          elif test("[.:;!?。：；！？…]$") then . + " " + $l
                          else . + " · " + $l end);
  # One line, at most $n display columns (CJK/emoji count 2), cut at a word boundary.
  # ~120 columns ≈ 3 lines on an iPhone, so state line + this fits the 4-line preview.
  def brief($n):
    gsub("\\s+"; " ") as $s
    | (reduce ($s | explode)[] as $c ({w: 0, out: [], cut: false};
         if .cut then .
         else (.w + (if $c >= 11904 then 2 else 1 end)) as $w
              | if $w > $n then .cut = true else .w = $w | .out += [$c] end
         end)) as $r
    | if $r.cut then ($r.out | implode | sub("\\s+[!-~]{1,20}$"; "")) + "…" else $s end;  # drop a cut ASCII word
  # Opening prose of a message, headings skipped.
  def gist($n): [prose_lines[] | select(test("^\\s*#") | not) | inline] | join_lines | brief($n);

  if (.agent_id // "") != "" then empty

  elif .hook_event_name == "Test" then
    {body: "🔔 Test\nBark works on \($host).", level: "active", sound: ""}

  elif .hook_event_name == "PreToolUse" and .tool_name == "AskUserQuestion" then
    (.tool_input.questions // []) as $qs
    | {body: ("❓ Question"
              + (if ($qs | length) == 0 then ""
                 else "\n" + (($qs[0].question // "" | inline)
                   + ([$qs[0].options[]? | .label // tostring] as $o
                      | if ($o | length) > 0 then " (" + ($o | join(" / ")) + ")" else "" end)
                   + (if ($qs | length) > 1 then " +\(($qs | length) - 1) more" else "" end)
                   | brief(120))
                 end)),
       level: "timeSensitive", sound: $sound_ask}

  elif .hook_event_name == "PreToolUse" and .tool_name == "ExitPlanMode" then
    # Plan title = its first heading, else its opening line.
    ((.tool_input.plan // "") | ([prose_lines[] | select(test("^\\s*#"))][0] // prose_lines[0] // "")
     | inline | brief(90)) as $title
    | {body: ("📋 Plan ready" + (if $title != "" then "\n" + $title else "" end)),
       level: "timeSensitive", sound: $sound_ask}

  elif .hook_event_name == "Stop" then
    if .stop_hook_active == true
       or ((.background_tasks // []) | length) > 0
       or ((.session_crons // []) | length) > 0
    then empty
    else
      (.last_assistant_message // "" | gist(120)) as $gist
      | {body: ("✅ Finished" + (if $gist != "" then "\n" + $gist else "" end)),
         level: "active", sound: $sound_done}
    end

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
