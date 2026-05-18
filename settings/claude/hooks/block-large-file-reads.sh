#!/usr/bin/env bash
# Self-contained: no Python, no sibling _lib. Requires: bash, jq, wc.
# stdin: Claude/Codex Read PreToolUse hook JSON.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo >&2 "ai-coding-hooks: block-large-file-reads.sh requires jq on PATH"
  echo "{}"
  exit 0
fi

input=$(cat)
PATH_RAW=$(jq -r '.tool_input.file_path // .tool_input.path // .file_path // .path // ""' <<<"$input")
OFFSET=$(jq -r '.tool_input.offset // .offset // empty' <<<"$input")
LIMIT=$(jq -r '.tool_input.limit // .limit // empty' <<<"$input")
CWD=$(jq -r '.cwd // empty' <<<"$input")

allow_out() {
  if jq -e '.hook_event_name != null' <<<"$input" >/dev/null 2>&1; then
    echo "{}"
  else
    jq -n '{permission:"allow"}'
  fi
}

deny_claude_family() {
  local reason=$1 ev=$2
  jq -n --arg reason "$reason" --arg ev "$ev" \
    '{hookSpecificOutput:{hookEventName:$ev,permissionDecision:"deny",permissionDecisionReason:$reason}}'
}

deny_cursor() {
  local reason=$1
  jq -n --arg reason "$reason" '{permission:"deny",user_message:$reason,agent_message:$reason}'
}

if [[ -z "$PATH_RAW" || -n "$OFFSET" || -n "$LIMIT" ]]; then
  allow_out
  exit 0
fi

case "$PATH_RAW" in
  ~/*) FILE="${HOME}/${PATH_RAW#~/}" ;;
  /*) FILE="$PATH_RAW" ;;
  *) FILE="${CWD:-$PWD}/$PATH_RAW" ;;
esac

if [[ ! -f "$FILE" ]]; then
  allow_out
  exit 0
fi

LINE_COUNT=$(wc -l <"$FILE" | tr -d '[:space:]')

if [[ "$LINE_COUNT" =~ ^[0-9]+$ && "$LINE_COUNT" -gt 500 ]]; then
  REASON="blocked read: '$PATH_RAW' has ${LINE_COUNT} lines. Re-run Read with offset and limit, for example offset=1 limit=200, then continue in sequential chunks until the file is fully covered. Max limit is 500 lines."
  if jq -e '.hook_event_name != null' <<<"$input" >/dev/null 2>&1; then
    EV=$(jq -r '.hook_event_name // "PreToolUse"' <<<"$input")
    deny_claude_family "$REASON" "$EV"
  else
    deny_cursor "$REASON"
  fi
  exit 0
fi

allow_out
exit 0
