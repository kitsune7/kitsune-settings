#!/usr/bin/env bash
# Self-contained: no Python, no sibling _lib. Requires: bash, jq.
# stdin: agent hook JSON (Cursor beforeShell / preTool Shell, or Claude/Codex PreToolUse Bash).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo >&2 "ai-coding-hooks: block-dangerous-shell.sh requires jq on PATH"
  echo "{}"
  exit 0
fi

input=$(cat)
CMD=$(jq -r '.command // .tool_input.command // ""' <<<"$input")
CMD_TRIM="${CMD//[[:space:]]/}"

deny_cursor() {
  local r=$1
  jq -n --arg r "$r" '{permission:"deny",user_message:$r,agent_message:$r}'
}

deny_claude_family() {
  local r=$1 ev=$2
  jq -n --arg r "$r" --arg ev "$ev" \
    '{hookSpecificOutput:{hookEventName:$ev,permissionDecision:"deny",permissionDecisionReason:$r}}'
}

allow_out() {
  if jq -e '.hook_event_name != null' <<<"$input" >/dev/null 2>&1; then
    echo "{}"
  else
    jq -n '{permission:"allow"}'
  fi
}

if [[ -z "$CMD_TRIM" ]]; then
  allow_out
  exit 0
fi

NORM=$(echo "$CMD" | tr -s '[:space:]' ' ')
REASON=""

if echo "$NORM" | grep -qiE '(^|[;|&[:space:]])(curl|wget)[^|]*\|[[:space:]]*((sudo|env|command)[[:space:]]+)*(sh|bash|zsh)\b'; then
  REASON="refused: piping remote download into a shell"
elif echo "$NORM" | grep -qiE '\b(sh|bash|zsh)[[:space:]]+-c[[:space:]]+.*\$\([[:space:]]*(curl|wget)\b'; then
  REASON="refused: executing remote download in a shell"
elif echo "$NORM" | grep -qiE '\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-+[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)\b.*[[:space:]](/|~|\$HOME)([[:space:]]|$)'; then
  REASON="refused: recursive force delete of broad paths"
elif echo "$NORM" | grep -qiE '\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-+[a-zA-Z]*f[a-zA-Z]*r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)\b.*[[:space:]](\*|\.)([[:space:]]|$)'; then
  REASON="refused: recursive force delete of broad globs"
elif echo "$NORM" | grep -qiE '\bmkfs\b'; then
  REASON="refused: mkfs"
elif echo "$NORM" | grep -qiE '\bdd[[:space:]].*of=/dev/'; then
  REASON="refused: dd to device"
elif echo "$NORM" | grep -qiE ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|:[[:space:]]*&'; then
  REASON="refused: fork bomb"
elif echo "$NORM" | grep -qiE 'chmod[[:space:]]+-R[[:space:]]+777'; then
  REASON="refused: chmod 777 -R"
elif echo "$NORM" | grep -qiE 'git[[:space:]]+push.*(--force|-f)'; then
  REASON="refused: force git push"
elif echo "$NORM" | grep -qiE '\b(cargo|npm|pnpm|bun)[[:space:]]+publish\b|yarn[[:space:]]+npm[[:space:]]+publish\b|gem[[:space:]]+push\b|twine[[:space:]]+upload\b'; then
  REASON="refused: package publish"
elif echo "$NORM" | grep -qiE 'aws[[:space:]].*(s3[[:space:]]+(rb|rm)|delete-bucket|terminate-instances|cloudformation[[:space:]]+delete-stack|lambda[[:space:]]+delete-function)'; then
  REASON="refused: destructive AWS CLI"
fi

if [[ -n "$REASON" ]]; then
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
