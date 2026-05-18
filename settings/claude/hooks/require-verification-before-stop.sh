#!/usr/bin/env bash
# Self-contained: no Python, no sibling _lib. Requires: bash, jq.
# stdin: Claude/Codex PostToolUse and Stop hook JSON.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo >&2 "ai-coding-hooks: require-verification-before-stop.sh requires jq on PATH"
  echo "{}"
  exit 0
fi

input=$(cat)
EVENT=$(jq -r '.hook_event_name // ""' <<<"$input")
TOOL_NAME=$(jq -r '.tool_name // ""' <<<"$input")
CWD=$(jq -r '.cwd // empty' <<<"$input")
SESSION_ID=$(jq -r '.session_id // .transcript_path // "unknown-session"' <<<"$input")
COMMAND=$(jq -r '.tool_input.command // .command // ""' <<<"$input")

STATE_ROOT="${TMPDIR:-/tmp}/claude-verification-hooks"
mkdir -p "$STATE_ROOT"
STATE_KEY=$(printf '%s\n%s\n' "$SESSION_ID" "${CWD:-$PWD}" | shasum | awk '{print $1}')
STATE_FILE="$STATE_ROOT/$STATE_KEY.state"

allow_out() {
  echo "{}"
}

record_state() {
  local key=$1 value=$2
  touch "$STATE_FILE"
  if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
    local tmp="${STATE_FILE}.$$"
    awk -v key="$key" -v value="$value" '
      BEGIN { replaced = 0 }
      index($0, key "=") == 1 { print key "=" value; replaced = 1; next }
      { print }
      END { if (!replaced) print key "=" value }
    ' "$STATE_FILE" >"$tmp"
    mv "$tmp" "$STATE_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$STATE_FILE"
  fi
}

read_state() {
  local key=$1
  if [[ -f "$STATE_FILE" ]]; then
    grep "^${key}=" "$STATE_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2-
  fi
}

is_write_tool() {
  case "$TOOL_NAME" in
    Edit|MultiEdit|Write|NotebookEdit) return 0 ;;
    *) return 1 ;;
  esac
}

is_verification_command() {
  local normalized
  normalized=$(echo "$COMMAND" | tr -s '[:space:]' ' ')

  [[ "$normalized" =~ (^|[[:space:];&|])(npx[[:space:]]+)?tsc([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ (^|[[:space:];&|])(npx[[:space:]]+)?eslint([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ (^|[[:space:];&|])(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(test|typecheck|type-check|lint)([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ (^|[[:space:];&|])pnpm([[:space:]]+((-F|--filter)[[:space:]]+[^[:space:];&|]+|-r|--recursive|--workspace-root))+[[:space:]]+(test|typecheck|type-check|lint)([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ (^|[[:space:];&|])(pytest|go[[:space:]]+test|cargo[[:space:]]+test|bundle[[:space:]]+exec[[:space:]]+rspec|rspec)([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ (^|[[:space:];&|])(uv[[:space:]]+run[[:space:]]+)?(pytest|ruff|mypy|pyright)([[:space:]]|$) ]] && return 0
  [[ "$normalized" =~ verification-unavailable: ]] && return 0

  return 1
}

command_succeeded() {
  local code is_error
  is_error=$(jq -r '.tool_response.is_error // false' <<<"$input")
  [[ "$is_error" == "true" ]] && return 1

  code=$(jq -r '.tool_response.exit_code // .tool_response.status // .exit_code // empty' <<<"$input")
  [[ -z "$code" || "$code" == "0" || "$code" == "success" ]]
}

if [[ "$EVENT" == "PostToolUse" ]]; then
  if is_write_tool; then
    record_state changed 1
    record_state verified 0
  elif [[ "$TOOL_NAME" == "Bash" ]] && is_verification_command && command_succeeded; then
    record_state verified 1
    record_state last_verification "$COMMAND"
  fi
  allow_out
  exit 0
fi

if [[ "$EVENT" == "Stop" ]]; then
  CHANGED=$(read_state changed)
  VERIFIED=$(read_state verified)

  if [[ "$CHANGED" == "1" && "$VERIFIED" != "1" ]]; then
    cat >&2 <<'MESSAGE'
Verification required before final response.

You edited files in this session but have not run a recognized verification command successfully yet.

How to fix:
1. Run the project's type-check command, such as `npx tsc --noEmit`, `npm run typecheck`, or the repo-specific equivalent.
2. Run lint/tests when configured, such as `npx eslint . --quiet`, `npm test`, `pytest`, `go test ./...`, or the repo-specific equivalent.
3. If the project has no relevant verifier, inspect the repo config, then run `echo "verification-unavailable: no configured typecheck, lint, or test command found"` and state that limitation in the final answer.
4. After verification succeeds, continue and send the final answer.
MESSAGE
    exit 2
  fi
fi

allow_out
exit 0
