#!/usr/bin/env bash
# Self-contained: no Python, no sibling _lib. Requires: bash, jq.
# stdin: agent hook JSON (Cursor beforeReadFile, or Claude/Codex Read PreToolUse).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo >&2 "ai-coding-hooks: block-secret-reads.sh requires jq on PATH"
  echo "{}"
  exit 0
fi

input=$(cat)
PATH_RAW=$(jq -r '
  .file_path // .tool_input.file_path // .tool_input.path // .tool_input.target_file // ""
' <<<"$input")

deny_cursor() {
  local r=$1
  jq -n --arg r "$r" '{permission:"deny",user_message:$r}'
}

deny_claude_family() {
  local r=$1 ev=$2
  jq -n --arg r "$r" --arg ev "$ev" \
    '{hookSpecificOutput:{hookEventName:$ev,permissionDecision:"deny",permissionDecisionReason:$r}}'
}

allow_out() {
  if jq -e '.hook_event_name != null' <<<"$input" >/dev/null 2>&1; then
    echo "{}"
  elif jq -e 'has("file_path") and has("content")' <<<"$input" >/dev/null 2>&1; then
    jq -n '{permission:"allow"}'
  else
    jq -n '{permission:"allow"}'
  fi
}

if [[ -z "$PATH_RAW" ]]; then
  allow_out
  exit 0
fi

# Normalize for substring checks (tilde expanded paths from agents are usually absolute).
# Prefixing with / lets the same glob catch absolute and relative dot-directory paths.
LOWER=$(echo "$PATH_RAW" | tr '[:upper:]' '[:lower:]')
LOWER_PATH="/${LOWER#./}"
BASE=$(basename "$PATH_RAW" | tr '[:upper:]' '[:lower:]')
REASON=""

is_example_path() {
  [[ "$LOWER" == *example* || "$LOWER" == *sample* || "$LOWER" == *template* ]]
}

if [[ "$BASE" == ".env" ]] || [[ "$BASE" == .env.* ]]; then
  if ! is_example_path; then
    REASON="blocked read: environment file"
  fi
fi

if [[ -z "$REASON" ]] && [[ "$LOWER_PATH" == *"/.ssh/"* ]]; then
  case "$BASE" in
    id_rsa|id_ed25519|id_ecdsa|id_dsa) REASON="blocked read: SSH private key material" ;;
    *.pem|*.key|*_rsa|*_ed25519|*_ecdsa|*_dsa) REASON="blocked read: SSH key-like file" ;;
  esac
fi

if [[ -z "$REASON" ]] && [[ "$LOWER_PATH" == *"/.aws/credentials" ]]; then
  REASON="blocked read: AWS CLI config"
fi

if [[ -z "$REASON" ]] && [[ "$LOWER_PATH" == *"/.gem/credentials" ]]; then
  REASON="blocked read: RubyGems credentials"
fi

if [[ -z "$REASON" ]] && [[ "$LOWER_PATH" == *"/.docker/config.json" ]]; then
  REASON="blocked read: Docker credential config"
fi

if [[ -z "$REASON" ]] && [[ "$BASE" == ".netrc" || "$BASE" == ".git-credentials" || "$BASE" == ".npmrc" || "$BASE" == ".pypirc" ]]; then
  REASON="blocked read: credential store"
fi

if [[ -z "$REASON" ]] && echo "$LOWER_PATH" | grep -qE 'gcloud[/\\]application_default_credentials\.json$'; then
  REASON="blocked read: GCP ADC file"
fi

if [[ -z "$REASON" ]] && [[ "$LOWER_PATH" == *"/.kube/config" ]]; then
  REASON="blocked read: kubeconfig"
fi

if [[ -z "$REASON" ]] && ! is_example_path; then
  case "$BASE" in
    credentials.json|service-account*.json|service_account*.json|*service-account-key*.json|*service_account_key*.json)
      REASON="blocked read: cloud credential JSON"
      ;;
  esac
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
