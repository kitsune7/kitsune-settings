#!/usr/bin/env bash
# Self-contained: no Python. Requires: bash, jq, curl.
# stdin: agent hook JSON (Cursor beforeShell / preTool Shell, or Claude/Codex PreToolUse Bash).
#
# Blocks package install and remote-exec commands unless the package is on the
# public registry and does not look like obvious malware. This is aimed at the
# llms.txt / docs supply-chain pattern: an agent copies an install line whose
# package name was never registered, then an attacker claims that name.
#
# Fast path is deterministic: missing package, npm security placeholders,
# install scripts that download a shell, typosquats of popular packages with
# almost no downloads, and packages published in the last two days (seven days
# for npx-style execution) with almost no downloads.
#
# Ambiguous install scripts on unpopular npm packages are judged by a local
# OpenAI-compatible model at http://localhost:1234 (model gpt-6-luna). The
# model only sees metadata this script already fetched.
#
# Bash 3.2 compatible (macOS /bin/bash).
set -euo pipefail

FRESH_HOURS=48
EXECUTE_FRESH_HOURS=168
FRESH_MAX_WEEKLY_DOWNLOADS=1000
TYPOSQUAT_MAX_WEEKLY_DOWNLOADS=1000
SCRIPT_REVIEW_MAX_WEEKLY_DOWNLOADS=20000
ALLOW_CACHE_SECONDS=43200
DENY_CACHE_SECONDS=1800
UA="kitsune-settings-package-hook"
MODEL_URL="http://localhost:1234/v1/chat/completions"
MODEL_NAME="gpt-6-luna"

NPM_POPULAR="react react-dom next vue express lodash axios webpack typescript eslint prettier commander chalk debug moment underscore jquery svelte vite rollup mocha jest vitest redux rxjs mongoose uuid dotenv cors nodemon zod prisma tailwindcss postcss esbuild semver glob yargs inquirer fs-extra electron request"
PYPI_POPULAR="requests urllib3 numpy pandas flask django scipy matplotlib pillow boto3 botocore setuptools pytest pydantic fastapi sqlalchemy cryptography pyyaml jinja2 click httpx aiohttp werkzeug gunicorn uvicorn scrapy celery beautifulsoup4 ruff"
CARGO_POPULAR="serde tokio clap regex rand quote libc anyhow thiserror serde_json reqwest bytes futures tracing axum hyper chrono once_cell memchr hashbrown indexmap bitflags async-trait"
GEM_POPULAR="rails nokogiri bundler rspec devise sidekiq faraday minitest rubocop activerecord activesupport"

DEPTH=0
CWD=""
WORKDIR=""
CACHE_DIR=""
REASONS=""
ARGS=()

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
  if jq -e '.hook_event_name != null' <<<"$INPUT" >/dev/null 2>&1; then
    echo "{}"
  else
    jq -n '{permission:"allow"}'
  fi
}

deny_out() {
  local r=$1
  if jq -e '.hook_event_name != null' <<<"$INPUT" >/dev/null 2>&1; then
    local ev
    ev=$(jq -r '.hook_event_name // "PreToolUse"' <<<"$INPUT")
    deny_claude_family "$r" "$ev"
  else
    deny_cursor "$r"
  fi
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

uri_encode() {
  jq -nr --arg s "$1" '$s|@uri'
}

one_line() {
  printf '%s' "$1" | tr '\t\n\r' '   ' | cut -c 1-420
}

cache_path() {
  local key
  key=$(printf '%s' "$1" | shasum -a 256 | awk '{print $1}')
  printf '%s/%s' "$CACHE_DIR" "$key"
}

cache_get() {
  local f exp decision reason now
  f=$(cache_path "$1")
  [[ -f "$f" ]] || return 1
  IFS=$'\t' read -r exp decision reason <"$f" || return 1
  now=$(date +%s)
  [[ "$exp" =~ ^[0-9]+$ ]] || return 1
  (( now < exp )) || return 1
  if [[ "$decision" == allow ]]; then
    printf 'allow'
  else
    printf 'deny\t%s' "$reason"
  fi
}

cache_put() {
  local key=$1 decision=$2 reason=$3 ttl=$4
  local exp f
  exp=$(( $(date +%s) + ttl ))
  f=$(cache_path "$key")
  printf '%s\t%s\t%s\n' "$exp" "$decision" "$(one_line "$reason")" >"$f"
}

http_get() {
  local url=$1 out=$2 code
  code=$(curl -sS -L --max-time 8 --connect-timeout 3 \
    -A "$UA" \
    -o "$out" \
    -w "%{http_code}" \
    "$url" 2>"$out.err" || printf '000')
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    code=${code: -3}
  fi
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    code=000
  fi
  printf '%s' "$code"
}

iso_to_epoch() {
  local raw=$1 datepart timepart epoch
  [[ -z "$raw" || "$raw" == "null" ]] && return 1
  raw=${raw%%.*}
  raw=${raw%Z}
  if [[ "$raw" == *T*+* ]]; then
    raw=${raw%%+*}
  fi
  if [[ "$raw" == *T* ]]; then
    datepart=${raw%%T*}
    timepart=${raw#*T}
    timepart=${timepart%%-*}
    raw="${datepart}T${timepart}"
  fi
  epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$raw" +%s 2>/dev/null) || \
    epoch=$(date -u -d "$raw" +%s 2>/dev/null) || return 1
  printf '%s' "$epoch"
}

age_hours() {
  local epoch now
  epoch=$(iso_to_epoch "$1") || return 1
  now=$(date -u +%s)
  if (( epoch > now )); then
    printf '0'
    return 0
  fi
  printf '%s' $(( (now - epoch) / 3600 ))
}

dist_one() {
  local a=$1 b=$2 la lb i j skipped diff
  la=${#a}
  lb=${#b}
  if (( la > lb )); then
    dist_one "$b" "$a" && return 0
    return 1
  fi
  if (( lb - la > 1 )); then
    return 1
  fi
  if (( la == lb )); then
    [[ "$a" == "$b" ]] && return 1
    local first=-1 second=-1
    for ((i = 0; i < la; i++)); do
      if [[ "${a:i:1}" != "${b:i:1}" ]]; then
        if (( first < 0 )); then
          first=$i
        elif (( second < 0 )); then
          second=$i
        else
          return 1
        fi
      fi
    done
    if (( second < 0 )); then
      return 0
    fi
    # Adjacent transposition (lodahs/lodash), which edit-distance 1 misses.
    if (( second == first + 1 )) \
      && [[ "${a:first:1}" == "${b:second:1}" && "${a:second:1}" == "${b:first:1}" ]]; then
      return 0
    fi
    return 1
  fi
  i=0
  j=0
  skipped=0
  while (( i < la && j < lb )); do
    if [[ "${a:i:1}" == "${b:j:1}" ]]; then
      i=$((i + 1))
      j=$((j + 1))
    else
      (( skipped == 1 )) && return 1
      skipped=1
      j=$((j + 1))
    fi
  done
  if (( skipped == 1 && i == la && j == lb )); then
    return 0
  fi
  if (( skipped == 0 && i == la && j == lb - 1 )); then
    return 0
  fi
  return 1
}

looks_like_typosquat() {
  local name=$1 list=$2 base n
  base=$(lower "$name")
  base=${base##*/}
  [[ ${#base} -ge 5 ]] || return 1
  for n in $list; do
    [[ "$n" == "$base" ]] && return 1
    [[ ${#n} -lt 5 ]] && continue
    if dist_one "$base" "$n"; then
      return 0
    fi
  done
  return 1
}

name_is_suspicious_text() {
  local name=$1
  if printf '%s' "$name" | LC_ALL=C grep -q '[^A-Za-z0-9._~@+/-]'; then
    return 0
  fi
  return 1
}

script_is_malware() {
  local s=$1
  [[ -z "$s" ]] && return 1
  printf '%s' "$s" | grep -qiE \
    'curl[[:space:]][^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)|wget[[:space:]][^|;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)|base64[[:space:]]+(-d|--decode)|/dev/tcp|bash[[:space:]]+-i([[:space:]]|$)|powershell.*(downloadstring|invoke-expression)|[[:space:];|&]iex[[:space:]]|invoke-webrequest|xmrig|stratum\+tcp|coinhive|discord(app)?\.com/api/webhooks|eval[[:space:]]*\([[:space:]]*(buffer\.from|atob)|child_process[[:space:]]*\.(exec|spawn)[^;\n]*(curl|wget)|[[:space:]]nc[[:space:]]+[^;\n]*-e[[:space:]]|ncat[[:space:]]' \
    >/dev/null
}

script_is_benign() {
  local s
  s=$(printf '%s' "$1" | tr -s '[:space:]' ' ')
  s=${s# }
  s=${s% }
  case "$s" in
    ""|true|"exit 0"|"node-gyp rebuild"|"node-gyp-build"|"prebuild-install"|"husky"|"husky install")
      return 0
      ;;
  esac
  printf '%s' "$s" | grep -qiE '^(node-gyp|node-gyp-build|prebuild-install|husky)([[:space:]]|$)' && return 0
  printf '%s' "$s" | grep -qiE '^echo([[:space:]]|$)' && return 0
  return 1
}

script_needs_review() {
  local s=$1
  script_is_benign "$s" && return 1
  [[ -n "$s" ]]
}

host_of_url() {
  local u=$1
  u=${u#git+}
  u=${u#ssh://}
  if [[ "$u" == git@*:* ]]; then
    u=${u#git@}
    u=${u%%:*}
    lower "$u"
    return
  fi
  u=${u#*://}
  u=${u%%/*}
  u=${u%%\?*}
  u=${u#*@}
  u=${u%%:*}
  lower "$u"
}

host_allowed() {
  local h=$1
  case "$h" in
    github.com|www.github.com|gitlab.com|www.gitlab.com|bitbucket.org| \
      registry.npmjs.org|registry.yarnpkg.com| \
      files.pythonhosted.org|pypi.org|pypi.python.org| \
      static.crates.io|index.crates.io|crates.io| \
      rubygems.org|index.rubygems.org| \
      proxy.golang.org|sum.golang.org| \
      codeload.github.com|repo.packagist.org|packagist.org| \
      api.nuget.org|globalcdn.nuget.org)
      return 0
      ;;
  esac
  case "$h" in
    *.github.com|*.githubusercontent.com|*.gitlab.com) return 0 ;;
  esac
  return 1
}

is_local_spec() {
  local s=$1
  case "$s" in
    .|..|./*|../*|/*|~/*|file:*|link:*|workspace:*|portal:*) return 0 ;;
  esac
  case "$s" in
    *.tgz|*.tar.gz|*.whl|*.zip)
      if [[ -e "$s" || -e "$CWD/$s" ]]; then
        return 0
      fi
      ;;
  esac
  return 1
}

add_reason() {
  local r
  r=$(one_line "$1")
  [[ -z "$r" ]] && return 0
  if [[ -z "$REASONS" ]]; then
    REASONS=$r
  else
    REASONS="${REASONS}; ${r}"
  fi
}

add_check() {
  local eco=$1 name=$2 ver=$3 mode=$4 review=${5:-review}
  [[ -z "$name" ]] && return 0
  case "${name}${ver}" in
    *\|*)
      add_reason "blocked package install: package name '${name}' contains unexpected characters"
      return 0
      ;;
  esac
  # Pipe, not tab: bash read collapses empty tab fields, which dropped the version column.
  printf '%s|%s|%s|%s|%s\n' "$eco" "$name" "$ver" "$mode" "$review" >>"$WORKDIR/checks"
}

note_url_spec() {
  local spec=$1
  case "$spec" in
    github:*|gitlab:*|bitbucket:*) return 0 ;;
    git@github.com:*|git@gitlab.com:*|git@bitbucket.org:*|ssh://git@github.com/*|ssh://git@gitlab.com/*)
      return 0
      ;;
  esac
  local host
  host=$(host_of_url "$spec")
  if host_allowed "$host"; then
    return 0
  fi
  add_reason "blocked package install: refusing to download from unrecognized host '${host:-$spec}'. Install scripts and docs sometimes point at untrusted URLs."
}

npm_registry_for() {
  local name=$1 scope="" reg="" f line
  if [[ "$name" == @*/* ]]; then
    scope=${name%%/*}
  fi
  if [[ -n "$scope" ]]; then
    for f in "$CWD/.npmrc" "$HOME/.npmrc"; do
      [[ -f "$f" ]] || continue
      line=$(grep -E "^${scope}:registry=" "$f" 2>/dev/null | tail -n 1 || true)
      if [[ -n "$line" ]]; then
        reg=${line#*=}
        break
      fi
    done
  fi
  if [[ -z "$reg" ]]; then
    for f in "$CWD/.npmrc" "$HOME/.npmrc"; do
      [[ -f "$f" ]] || continue
      line=$(grep -E '^registry=' "$f" 2>/dev/null | tail -n 1 || true)
      if [[ -n "$line" ]]; then
        reg=${line#*=}
        break
      fi
    done
  fi
  reg=${reg:-https://registry.npmjs.org}
  reg=${reg%/}
  printf '%s' "$reg"
}

is_public_npm_registry() {
  case "$1" in
    https://registry.npmjs.org|http://registry.npmjs.org|https://registry.yarnpkg.org|https://registry.yarnpkg.com)
      return 0
      ;;
  esac
  return 1
}

is_exact_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.]+)?$ ]]
}

queue_npm_spec() {
  local spec=$1 mode=$2 review=$3 name version rest
  spec=$(printf '%s' "$spec" | tr -d '[:space:]')
  [[ -z "$spec" ]] && return 0
  if is_local_spec "$spec"; then
    return 0
  fi
  case "$spec" in
    git+*|git://*|git@*|github:*|gitlab:*|bitbucket:*|http://*|https://*|ssh://*)
      note_url_spec "$spec"
      return 0
      ;;
  esac
  if [[ "$spec" == @* ]]; then
    rest=${spec#@}
    if [[ "$rest" == *@* ]]; then
      name="@${rest%%@*}"
      version=${rest#*@}
    else
      name="@${rest}"
      version=""
    fi
  else
    case "$spec" in
      *@*)
        name=${spec%%@*}
        version=${spec#*@}
        ;;
      *)
        name=$spec
        version=""
        ;;
    esac
  fi
  if [[ "$version" == npm:* ]]; then
    queue_npm_spec "${version#npm:}" "$mode" "$review"
    return 0
  fi
  case "$version" in
    file:*|link:*|workspace:*|portal:*|git+*|git:*|github:*|gitlab:*|bitbucket:*|http:*|https:*|ssh:*)
      note_url_spec "$version"
      return 0
      ;;
  esac
  name=$(lower "$name")
  if [[ "$version" == "latest" || "$version" == "*" || "$version" == "x" ]]; then
    version=""
  fi
  if [[ -n "$version" ]] && ! is_exact_version "$version"; then
    case "$version" in
      ^*|~*|*\>*|*\<*|*\|\|*|*\ *|*\x*) version="" ;;
    esac
  fi
  if [[ "$mode" == execute && -n "$CWD" ]]; then
    local bin=$name
    bin=${bin##*/}
    if [[ -z "$version" && ( -x "$CWD/node_modules/.bin/$bin" || -x "$CWD/node_modules/.bin/$name" ) ]]; then
      return 0
    fi
  fi
  add_check npm "$name" "$version" "$mode" "$review"
}

pypi_name_from_req() {
  local s=$1 name
  s=${s%%;*}
  s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  if printf '%s' "$s" | grep -q '://'; then
    printf '%s' "$s"
    return
  fi
  name=${s%%[*}
  name=$(printf '%s' "$name" | sed -E 's/[[:space:]]*(==|>=|<=|!=|~=|>|<).*//')
  name=$(printf '%s' "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  lower "$name"
}

queue_pypi_req() {
  local req=$1 mode=$2
  local name
  [[ -z "$req" ]] && return 0
  case "$req" in
    -*) return 0 ;;
  esac
  if printf '%s' "$req" | grep -q '://\|git+\|git@'; then
    note_url_spec "$req"
    return 0
  fi
  if is_local_spec "$req"; then
    return 0
  fi
  name=$(pypi_name_from_req "$req")
  [[ -z "$name" || "$name" == "." || "$name" == ".." ]] && return 0
  if is_local_spec "$name"; then
    return 0
  fi
  add_check pypi "$name" "" "$mode" skip-review
}

queue_requirements_file() {
  local file=$1 mode=$2 line target
  case "$file" in
    ~/*) file="${HOME}/${file#~/}" ;;
    /*) ;;
    *) file="$CWD/$file" ;;
  esac
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    [[ -z "$line" ]] && continue
    case "$line" in
      -r\ *|--requirement\ *)
        target=${line#* }
        queue_requirements_file "$target" "$mode"
        ;;
      -e\ *|--editable\ *)
        target=${line#* }
        if is_local_spec "$target"; then
          continue
        fi
        note_url_spec "$target"
        ;;
      --*) ;;
      *) queue_pypi_req "$line" "$mode" ;;
    esac
  done <"$file"
}

go_escape() {
  local s=$1 i c out=
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ "$c" =~ [A-Z] ]]; then
      out="${out}!$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')"
    else
      out="${out}${c}"
    fi
  done
  printf '%s' "$out"
}

ask_model() {
  local facts=$1 payload resp code body content json decision reason
  facts=${facts:0:7000}
  payload=$(jq -n --arg model "$MODEL_NAME" --arg facts "$facts" '{
    model: $model,
    temperature: 0,
    max_tokens: 160,
    messages: [
      {role:"system", content:"You screen one package install for obvious malware. You cannot browse. Use only the facts in the user message. Allow packages that look new, small, or boring, and allow install scripts that download that package'\''s own release binaries (esbuild, sharp, puppeteer style). Deny remote shells, credential theft, obfuscated eval of downloaded code, crypto miners, webhook exfiltration, and names impersonating a well-known package. Reply with one JSON object and nothing else: {\"allow\":true|false,\"reason\":\"short\"}"},
      {role:"user", content:$facts}
    ]
  }') || return 2
  resp=$(curl -sS --max-time 12 --connect-timeout 2 \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    -w '\n%{http_code}' \
    "$MODEL_URL" || true)
  [[ -n "$resp" ]] || return 2
  code=$(printf '%s\n' "$resp" | tail -n 1)
  body=$(printf '%s\n' "$resp" | sed '$d')
  [[ "$code" == "200" ]] || return 2
  content=$(printf '%s' "$body" | jq -r '.choices[0].message.content // empty' 2>/dev/null) || return 2
  [[ -n "$content" ]] || return 2
  json=$(printf '%s' "$content" | sed -E '1s/^```(json)?[[:space:]]*//; $s/[[:space:]]*```$//')
  decision=$(printf '%s' "$json" | jq -r 'if type=="object" then (.allow|tostring) else empty end' 2>/dev/null || true)
  reason=$(printf '%s' "$json" | jq -r 'if type=="object" then (.reason // "") else empty end' 2>/dev/null || true)
  if [[ -z "$decision" ]]; then
    json=$(printf '%s' "$content" | sed -n 's/.*\(\{.*\}\).*/\1/p' | head -n 1)
    decision=$(printf '%s' "$json" | jq -r '(.allow|tostring)' 2>/dev/null || true)
    reason=$(printf '%s' "$json" | jq -r '.reason // ""' 2>/dev/null || true)
  fi
  case "$decision" in
    true) return 0 ;;
    false)
      printf '%s' "${reason:-local model rejected the package}"
      return 1
      ;;
  esac
  return 2
}

lifecycle_scripts_of() {
  local manifest=$1
  jq -r '
    (.scripts // {})
    | to_entries[]
    | select(.key == "preinstall" or .key == "install" or .key == "postinstall")
    | "\(.key): \(.value)"
  ' "$manifest" 2>/dev/null || true
}

review_npm_scripts() {
  local manifest=$1 name=$2 ver=$3 downloads=$4 created=$5 desc=$6 dir=$7
  local scripts script js_path excerpt tarball model_reason
  scripts=$(lifecycle_scripts_of "$manifest")
  [[ -z "$scripts" ]] && return 0
  if script_is_malware "$scripts"; then
    printf '%s' "blocked package install: npm package '${name}' has an install script that matches a remote-shell or malware pattern"
    return 1
  fi
  script_needs_review "$scripts" || return 0
  if (( downloads >= SCRIPT_REVIEW_MAX_WEEKLY_DOWNLOADS )); then
    return 0
  fi
  js_path=$(printf '%s' "$scripts" | grep -oE '[[:alnum:]./_-]+\.js' | head -n 1 || true)
  excerpt=""
  if [[ -n "$js_path" && "$js_path" != *..* && "$js_path" != *node_modules* ]]; then
    tarball=$(jq -r '.dist.tarball // empty' "$manifest" 2>/dev/null || true)
    if [[ -n "$tarball" ]]; then
      local tgz="$dir/pkg.tgz" code rel
      rel=${js_path#./}
      code=$(http_get "$tarball" "$tgz")
      if [[ "$code" == "200" ]]; then
        excerpt=$(tar -xOf "$tgz" "package/${rel}" 2>/dev/null | head -c 6000 || true)
      fi
    fi
  fi
  if [[ -n "$excerpt" ]] && script_is_malware "$excerpt"; then
    printf '%s' "blocked package install: npm package '${name}' install script file looks like malware"
    return 1
  fi
  local facts
  facts=$(cat <<EOF
ecosystem: npm
name: ${name}
version: ${ver}
weekly_downloads: ${downloads}
first_published: ${created:-unknown}
description: ${desc}
lifecycle scripts:
${scripts}
EOF
)
  if [[ -n "$excerpt" ]]; then
    facts="${facts}
referenced file ${js_path}, truncated:
${excerpt}"
  fi
  if model_reason=$(ask_model "$facts"); then
    return 0
  fi
  local st=$?
  if (( st == 1 )); then
    printf '%s' "blocked package install: npm package '${name}' install script was rejected (${model_reason})"
    return 1
  fi
  printf '%s' "blocked package install: npm package '${name}' has a suspicious install script and the local review model at localhost:1234 was unavailable"
  return 1
}

check_npm() {
  local name=$1 ver=$2 mode=$3 review=$4
  local dir reg enc manifest_url dl_url mcode dcode downloads created desc version scripts hours reason
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: npm package name '${name}' contains unexpected characters"
    return 1
  fi
  dir="$WORKDIR/npm.$$.$RANDOM"
  mkdir -p "$dir"
  reg=$(npm_registry_for "$name")
  enc=$(uri_encode "$name")
  if [[ -n "$ver" ]]; then
    manifest_url="${reg}/${enc}/$(uri_encode "$ver")"
  else
    manifest_url="${reg}/${enc}/latest"
  fi
  if is_public_npm_registry "$reg"; then
    dl_url="https://api.npmjs.org/downloads/point/last-week/${enc}"
    http_get "$manifest_url" "$dir/manifest" >"$dir/manifest.code" &
    http_get "$dl_url" "$dir/downloads" >"$dir/dl.code" &
    wait || true
    mcode=$(cat "$dir/manifest.code" 2>/dev/null || echo 000)
    dcode=$(cat "$dir/dl.code" 2>/dev/null || echo 000)
  else
    mcode=$(http_get "$manifest_url" "$dir/manifest")
    dcode=""
  fi
  if [[ "$mcode" == "404" ]]; then
    printf '%s' "blocked package install: npm package '${name}${ver:+@$ver}' was not found on ${reg}. Unregistered names copied from docs or llms.txt are a common way to get an agent to run an attacker-controlled package."
    return 1
  fi
  if [[ "$mcode" == "401" || "$mcode" == "403" ]]; then
    if is_public_npm_registry "$reg"; then
      printf '%s' "blocked package install: npm registry refused metadata for '${name}' (HTTP ${mcode})"
      return 1
    fi
    return 0
  fi
  if [[ "$mcode" != "200" ]]; then
    printf '%s' "blocked package install: could not verify npm package '${name}' (registry HTTP ${mcode})"
    return 1
  fi
  version=$(jq -r '.version // empty' "$dir/manifest" 2>/dev/null || true)
  desc=$(jq -r '.description // ""' "$dir/manifest" 2>/dev/null || true)
  if printf '%s' "$version" | grep -qiE -- '-security([.+]|$)'; then
    printf '%s' "blocked package install: npm package '${name}' is an npm security placeholder (version ${version})"
    return 1
  fi
  if printf '%s' "$desc" | grep -qiE 'security holding|contained malware|malicious code|this package is malicious|removed for malware'; then
    printf '%s' "blocked package install: npm package '${name}' is marked as malicious or a security placeholder"
    return 1
  fi
  scripts=$(lifecycle_scripts_of "$dir/manifest")
  if script_is_malware "$scripts"; then
    printf '%s' "blocked package install: npm package '${name}' has an install script that matches a remote-shell or malware pattern"
    return 1
  fi

  downloads=-1
  if is_public_npm_registry "$reg"; then
    if [[ "$dcode" == "200" ]]; then
      downloads=$(jq -r '.downloads // 0' "$dir/downloads" 2>/dev/null || echo 0)
    elif [[ "$dcode" == "404" ]]; then
      downloads=0
    fi
  else
    if [[ "$review" != skip-review ]]; then
      reason=$(review_npm_scripts "$dir/manifest" "$name" "${version:-$ver}" 0 "" "$desc" "$dir") || {
        printf '%s' "$reason"
        return 1
      }
    fi
    return 0
  fi

  if [[ "$downloads" =~ ^[0-9]+$ ]] && (( downloads >= SCRIPT_REVIEW_MAX_WEEKLY_DOWNLOADS )); then
    return 0
  fi

  created=$(jq -r '.time.created // empty' "$dir/manifest" 2>/dev/null || true)
  if [[ -z "$created" ]]; then
    local pcode
    pcode=$(http_get "${reg}/${enc}" "$dir/packument")
    if [[ "$pcode" == "200" ]]; then
      created=$(jq -r '.time.created // empty' "$dir/packument" 2>/dev/null || true)
    fi
  fi

  if ! [[ "$downloads" =~ ^[0-9]+$ ]]; then
    printf '%s' "blocked package install: could not verify download history for npm package '${name}'"
    return 1
  fi

  if looks_like_typosquat "$name" "$NPM_POPULAR" && (( downloads < TYPOSQUAT_MAX_WEEKLY_DOWNLOADS )); then
    printf '%s' "blocked package install: npm package '${name}' is one character off a popular package and has ${downloads} weekly downloads"
    return 1
  fi

  if [[ -n "$created" ]]; then
    hours=$(age_hours "$created" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]]; then
      if (( hours < FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
        printf '%s' "blocked package install: npm package '${name}' was first published ${hours}h ago and has ${downloads} weekly downloads. That matches a freshly registered unclaimed name. Install it yourself if you trust it."
        return 1
      fi
      if [[ "$mode" == execute ]] && (( hours < EXECUTE_FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
        printf '%s' "blocked package install: refusing to execute npm package '${name}', first published ${hours}h ago with ${downloads} weekly downloads. Remote runners such as npx will run whatever currently owns that name."
        return 1
      fi
    fi
  elif (( downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
    printf '%s' "blocked package install: could not verify the publish date of npm package '${name}', which has ${downloads} weekly downloads"
    return 1
  fi

  if [[ "$review" != skip-review ]]; then
    reason=$(review_npm_scripts "$dir/manifest" "$name" "${version:-$ver}" "$downloads" "$created" "$desc" "$dir") || {
      printf '%s' "$reason"
      return 1
    }
  fi
  return 0
}

check_pypi() {
  local name=$1 mode=$2
  local dir code first count hours summary yanked
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: PyPI package name '${name}' contains unexpected characters"
    return 1
  fi
  dir="$WORKDIR/pypi.$$.$RANDOM"
  mkdir -p "$dir"
  code=$(http_get "https://pypi.org/pypi/$(uri_encode "$name")/json" "$dir/meta")
  if [[ "$code" == "404" ]]; then
    printf '%s' "blocked package install: PyPI package '${name}' was not found. Unregistered names copied from docs or llms.txt are a common way to get an agent to run an attacker-controlled package."
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify PyPI package '${name}' (HTTP ${code})"
    return 1
  fi
  yanked=$(jq -r '.info.yanked // false' "$dir/meta" 2>/dev/null || echo false)
  if [[ "$yanked" == "true" ]]; then
    printf '%s' "blocked package install: PyPI package '${name}' is yanked"
    return 1
  fi
  summary=$(jq -r '.info.summary // ""' "$dir/meta" 2>/dev/null || true)
  if printf '%s' "$summary" | grep -qiE 'this package is malicious|contained malware|security placeholder'; then
    printf '%s' "blocked package install: PyPI package '${name}' is described as malicious"
    return 1
  fi
  first=$(jq -r '[.releases[][]?.upload_time_iso_8601] | map(select(. != null and . != "")) | sort | .[0] // empty' "$dir/meta" 2>/dev/null || true)
  count=$(jq -r '(.releases // {}) | keys | length' "$dir/meta" 2>/dev/null || echo 0)
  if [[ -n "$first" ]]; then
    hours=$(age_hours "$first" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]]; then
      if (( hours < FRESH_HOURS )); then
        printf '%s' "blocked package install: PyPI package '${name}' was first uploaded ${hours}h ago. That matches a freshly registered unclaimed name. Install it yourself if you trust it."
        return 1
      fi
      if [[ "$mode" == execute ]] && (( hours < EXECUTE_FRESH_HOURS && count <= 2 )); then
        printf '%s' "blocked package install: refusing to execute PyPI package '${name}', first uploaded ${hours}h ago with ${count} release(s)"
        return 1
      fi
      if looks_like_typosquat "$name" "$PYPI_POPULAR" && (( hours < 720 )); then
        printf '%s' "blocked package install: PyPI package '${name}' is one character off a popular package and was first uploaded ${hours}h ago"
        return 1
      fi
    fi
  fi
  return 0
}

check_cargo() {
  local name=$1 mode=$2
  local dir code created downloads hours
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: crates.io package name '${name}' contains unexpected characters"
    return 1
  fi
  dir="$WORKDIR/cargo.$$.$RANDOM"
  mkdir -p "$dir"
  code=$(http_get "https://crates.io/api/v1/crates/$(uri_encode "$name")" "$dir/meta")
  if [[ "$code" == "404" ]]; then
    printf '%s' "blocked package install: crates.io package '${name}' was not found"
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify crates.io package '${name}' (HTTP ${code})"
    return 1
  fi
  created=$(jq -r '.crate.created_at // empty' "$dir/meta" 2>/dev/null || true)
  downloads=$(jq -r '.crate.downloads // 0' "$dir/meta" 2>/dev/null || echo 0)
  if [[ -n "$created" ]]; then
    hours=$(age_hours "$created" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]] && (( hours < FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
      printf '%s' "blocked package install: crate '${name}' was published ${hours}h ago and has ${downloads} downloads"
      return 1
    fi
    if [[ "$mode" == execute && "$hours" =~ ^[0-9]+$ ]] && (( hours < EXECUTE_FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
      printf '%s' "blocked package install: refusing to install fresh crate '${name}' (${hours}h old, ${downloads} downloads)"
      return 1
    fi
  fi
  if [[ "$downloads" =~ ^[0-9]+$ ]] && looks_like_typosquat "$name" "$CARGO_POPULAR" && (( downloads < TYPOSQUAT_MAX_WEEKLY_DOWNLOADS )); then
    printf '%s' "blocked package install: crate '${name}' is one character off a popular crate and has ${downloads} downloads"
    return 1
  fi
  return 0
}

check_gem() {
  local name=$1
  local dir code downloads created hours info version
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: RubyGems package name '${name}' contains unexpected characters"
    return 1
  fi
  dir="$WORKDIR/gem.$$.$RANDOM"
  mkdir -p "$dir"
  code=$(http_get "https://rubygems.org/api/v1/gems/$(uri_encode "$name").json" "$dir/meta")
  if [[ "$code" == "404" ]]; then
    printf '%s' "blocked package install: RubyGems package '${name}' was not found"
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify RubyGems package '${name}' (HTTP ${code})"
    return 1
  fi
  downloads=$(jq -r '.downloads // 0' "$dir/meta" 2>/dev/null || echo 0)
  created=$(jq -r '.created_at // empty' "$dir/meta" 2>/dev/null || true)
  version=$(jq -r '.version // empty' "$dir/meta" 2>/dev/null || true)
  info=$(jq -r '.info // ""' "$dir/meta" 2>/dev/null || true)
  if printf '%s' "$info" | grep -qiE 'this gem is malicious|contained malware|security placeholder'; then
    printf '%s' "blocked package install: gem '${name}' is described as malicious"
    return 1
  fi
  if [[ "$downloads" =~ ^[0-9]+$ ]] && (( downloads >= SCRIPT_REVIEW_MAX_WEEKLY_DOWNLOADS )); then
    return 0
  fi
  if [[ -n "$created" && "$created" != "null" ]]; then
    hours=$(age_hours "$created" || true)
    if [[ "$hours" =~ ^[0-9]+$ && "$downloads" =~ ^[0-9]+$ ]] && (( hours < FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
      printf '%s' "blocked package install: gem '${name}' was published ${hours}h ago and has ${downloads} downloads"
      return 1
    fi
  elif [[ "$downloads" =~ ^[0-9]+$ ]] && (( downloads < 300 )); then
    local vtime
    vtime=$(jq -r '.version_created_at // empty' "$dir/meta" 2>/dev/null || true)
    hours=$(age_hours "$vtime" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]] && (( hours < FRESH_HOURS )); then
      printf '%s' "blocked package install: gem '${name}' ${version} was published ${hours}h ago and has ${downloads} downloads"
      return 1
    fi
  fi
  if [[ "$downloads" =~ ^[0-9]+$ ]] && looks_like_typosquat "$name" "$GEM_POPULAR" && (( downloads < TYPOSQUAT_MAX_WEEKLY_DOWNLOADS )); then
    printf '%s' "blocked package install: gem '${name}' is one character off a popular gem and has ${downloads} downloads"
    return 1
  fi
  return 0
}

check_go() {
  local spec=$1 path ver enc code dir first
  path=$spec
  ver=""
  if [[ "$spec" == *@* ]]; then
    ver=${spec##*@}
    path=${spec%@*}
  fi
  case "$path" in
    .|..|./*|../*|/*) return 0 ;;
  esac
  first=${path%%/*}
  if [[ "$first" != *.* ]]; then
    return 0
  fi
  if [[ "$ver" =~ ^[0-9] ]]; then
    ver="v${ver}"
  fi
  dir="$WORKDIR/go.$$.$RANDOM"
  mkdir -p "$dir"
  local tries=0 found=""
  while (( tries < 6 )); do
    enc=$(go_escape "$path")
    code=$(http_get "https://proxy.golang.org/${enc}/@latest" "$dir/meta")
    if [[ "$code" == "200" ]]; then
      found=$path
      break
    fi
    if [[ "$code" != "404" && "$code" != "410" ]]; then
      printf '%s' "blocked package install: could not verify Go module '${spec}' (HTTP ${code})"
      return 1
    fi
    # cmd/stringer style: the module root is a parent of the install path.
    case "$path" in
      */*/*) path=${path%/*} ;;
      *) break ;;
    esac
    tries=$((tries + 1))
  done
  if [[ -z "$found" ]]; then
    printf '%s' "blocked package install: Go module '${spec}' was not found on the module proxy"
    return 1
  fi
  if [[ -n "$ver" && "$ver" != latest && "$ver" != none ]]; then
    enc=$(go_escape "$found")
    code=$(http_get "https://proxy.golang.org/${enc}/@v/${ver}.info" "$dir/ver")
    if [[ "$code" == "404" || "$code" == "410" ]]; then
      printf '%s' "blocked package install: Go module '${found}' has no version ${ver}"
      return 1
    fi
    if [[ "$code" != "200" ]]; then
      printf '%s' "blocked package install: could not verify Go module '${found}@${ver}' (HTTP ${code})"
      return 1
    fi
  fi
  return 0
}

check_composer() {
  local name=$1 dir code created hours
  if [[ "$name" != */* ]]; then
    printf '%s' "blocked package install: Composer package '${name}' is not a vendor/name coordinate"
    return 1
  fi
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: Composer package name '${name}' contains unexpected characters"
    return 1
  fi
  name=$(lower "$name")
  dir="$WORKDIR/composer.$$.$RANDOM"
  mkdir -p "$dir"
  code=$(http_get "https://repo.packagist.org/p2/${name}.json" "$dir/meta")
  if [[ "$code" == "404" ]]; then
    printf '%s' "blocked package install: Packagist package '${name}' was not found"
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify Packagist package '${name}' (HTTP ${code})"
    return 1
  fi
  created=$(jq -r --arg n "$name" '[.packages[$n][]?.time] | map(select(. != null and . != "")) | sort | .[0] // empty' "$dir/meta" 2>/dev/null || true)
  if [[ -n "$created" ]]; then
    hours=$(age_hours "$created" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]] && (( hours < FRESH_HOURS )); then
      printf '%s' "blocked package install: Packagist package '${name}' was first published ${hours}h ago"
      return 1
    fi
  fi
  return 0
}

check_nuget() {
  local name=$1 dir code id downloads published hours
  dir="$WORKDIR/nuget.$$.$RANDOM"
  mkdir -p "$dir"
  code=$(http_get "https://azuresearch-usnc.nuget.org/query?q=packageid:$(uri_encode "$name")&prerelease=true&take=5" "$dir/meta")
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify NuGet package '${name}' (HTTP ${code})"
    return 1
  fi
  id=$(jq -r --arg n "$(lower "$name")" '.data[]? | select((.id|ascii_downcase)==$n) | .id' "$dir/meta" 2>/dev/null | head -n 1 || true)
  if [[ -z "$id" ]]; then
    printf '%s' "blocked package install: NuGet package '${name}' was not found"
    return 1
  fi
  downloads=$(jq -r --arg n "$(lower "$name")" '.data[]? | select((.id|ascii_downcase)==$n) | .totalDownloads' "$dir/meta" 2>/dev/null | head -n 1 || echo 0)
  published=$(jq -r --arg n "$(lower "$name")" '.data[]? | select((.id|ascii_downcase)==$n) | .published // empty' "$dir/meta" 2>/dev/null | head -n 1 || true)
  if [[ "$downloads" =~ ^[0-9]+$ && -n "$published" ]]; then
    hours=$(age_hours "$published" || true)
    if [[ "$hours" =~ ^[0-9]+$ ]] && (( hours < FRESH_HOURS && downloads < FRESH_MAX_WEEKLY_DOWNLOADS )); then
      printf '%s' "blocked package install: NuGet package '${name}' was published ${hours}h ago and has ${downloads} downloads"
      return 1
    fi
  fi
  return 0
}

check_brew() {
  local name=$1 kind=$2 dir code url
  case "$name" in
    */*) return 0 ;;
  esac
  if name_is_suspicious_text "$name"; then
    printf '%s' "blocked package install: Homebrew formula name '${name}' contains unexpected characters"
    return 1
  fi
  dir="$WORKDIR/brew.$$.$RANDOM"
  mkdir -p "$dir"
  if [[ "$kind" == cask ]]; then
    url="https://formulae.brew.sh/api/cask/$(uri_encode "$name").json"
  else
    url="https://formulae.brew.sh/api/formula/$(uri_encode "$name").json"
  fi
  code=$(http_get "$url" "$dir/meta")
  if [[ "$code" == "404" ]]; then
    printf '%s' "blocked package install: Homebrew ${kind} '${name}' was not found"
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    printf '%s' "blocked package install: could not verify Homebrew ${kind} '${name}' (HTTP ${code})"
    return 1
  fi
  return 0
}

check_eco() {
  local eco=$1 name=$2 ver=$3 mode=$4 review=$5
  case "$eco" in
    npm) check_npm "$name" "$ver" "$mode" "$review" ;;
    pypi) check_pypi "$name" "$mode" ;;
    cargo) check_cargo "$name" "$mode" ;;
    gem) check_gem "$name" ;;
    go) check_go "$name" ;;
    composer) check_composer "$name" ;;
    nuget) check_nuget "$name" ;;
    brew) check_brew "$name" "$ver" ;;
    *)
      printf '%s' "blocked package install: unsupported ecosystem '${eco}'"
      return 1
      ;;
  esac
}

check_dispatch() {
  local eco=$1 name=$2 ver=$3 mode=$4 review=$5
  local key hit reason st
  key="${eco}|${name}|${ver}|${mode}|${review}"
  hit=$(cache_get "$key" || true)
  case "$hit" in
    allow) return 0 ;;
    deny*)
      printf '%s' "$(printf '%s' "$hit" | cut -f 2-)"
      return 1
      ;;
  esac
  reason=$(check_eco "$eco" "$name" "$ver" "$mode" "$review") && st=0 || st=$?
  if (( st == 0 )); then
    cache_put "$key" allow "" "$ALLOW_CACHE_SECONDS"
    return 0
  fi
  reason=$(one_line "$reason")
  case "$reason" in
    *"could not verify"*|*"could not reach"*|*"was unavailable"*)
      printf '%s' "$reason"
      return 1
      ;;
  esac
  cache_put "$key" deny "$reason" "$DENY_CACHE_SECONDS"
  printf '%s' "$reason"
  return 1
}

run_checks() {
  local line i=0
  sort -u "$WORKDIR/checks" >"$WORKDIR/checks.uniq"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    worker "$i" "$line" &
    i=$((i + 1))
    if (( i % 6 == 0 )); then
      wait || true
    fi
  done <"$WORKDIR/checks.uniq"
  wait || true
  local f decision reason got=0
  for f in "$WORKDIR"/r.*; do
    [[ -e "$f" ]] || continue
    got=$((got + 1))
    IFS=$'\t' read -r decision reason <"$f" || continue
    if [[ "$decision" == deny ]]; then
      add_reason "$reason"
    fi
  done
  if (( got < i )); then
    add_reason "blocked package install: package verification did not finish"
  fi
}

worker() {
  local idx=$1 line=$2 eco name ver mode review reason st
  set +e
  IFS='|' read -r eco name ver mode review <<<"$line"
  [[ -z "$review" ]] && review=review
  reason=$(check_dispatch "$eco" "$name" "$ver" "$mode" "$review")
  st=$?
  if (( st == 0 )); then
    printf 'allow\n' >"$WORKDIR/r.$idx"
  else
    printf 'deny\t%s\n' "${reason:-blocked package install: verification failed}" >"$WORKDIR/r.$idx"
  fi
}

token_kind() {
  local t=$1
  case "$t" in
    --) printf 'end'; return ;;
    --*=*) printf 'flag'; return ;;
  esac
  if [[ "$t" == -* ]]; then
    case " $VALUE_FLAGS " in
      *" $t "*) printf 'flag-value'; return ;;
    esac
    printf 'flag'
    return
  fi
  printf 'arg'
}

is_redirect_token() {
  case "$1" in
    '>'|'>>'|'<'|'&>'|'|&'|'2>&1'|'1>&2') return 0 ;;
  esac
  [[ "$1" =~ ^[0-9]*\>{1,2} ]] && return 0
  [[ "$1" =~ ^[0-9]*\< ]] && return 0
  return 1
}

set_args_from_line() {
  local line=$1 cur="" quote="" i c
  ARGS=()
  for ((i = 0; i < ${#line}; i++)); do
    c=${line:i:1}
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then
        quote=""
      else
        cur="${cur}${c}"
      fi
      continue
    fi
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      quote=$c
      continue
    fi
    if [[ "$c" == '\' ]]; then
      i=$((i + 1))
      cur="${cur}${line:i:1}"
      continue
    fi
    if [[ "$c" == ' ' || "$c" == $'\t' ]]; then
      if [[ -n "$cur" ]]; then
        ARGS+=("$cur")
        cur=""
      fi
      continue
    fi
    cur="${cur}${c}"
  done
  if [[ -n "$cur" ]]; then
    ARGS+=("$cur")
  fi
}

strip_wrappers() {
  local t
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    case "$t" in
      sudo|command|time|nohup|nice|exec)
        ARGS=("${ARGS[@]:1}")
        while (( ${#ARGS[@]} > 0 )); do
          case "${ARGS[0]}" in
            -*) ARGS=("${ARGS[@]:1}") ;;
            *) break ;;
          esac
        done
        ;;
      env)
        ARGS=("${ARGS[@]:1}")
        while (( ${#ARGS[@]} > 0 )); do
          case "${ARGS[0]}" in
            *=*) ARGS=("${ARGS[@]:1}") ;;
            *) break ;;
          esac
        done
        ;;
      *=*)
        ARGS=("${ARGS[@]:1}")
        ;;
      *)
        break
        ;;
    esac
  done
}

shift_arg() {
  if (( ${#ARGS[@]} > 0 )); then
    ARGS=("${ARGS[@]:1}")
  fi
}

# Walk ARGS, appending positional package args to a file. Honors VALUE_FLAGS.
collect_positionals() {
  local out=$1 stop_after_first=${2:-0} count=0 t kind
  : >"$out"
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    shift_arg
    if is_redirect_token "$t"; then
      case "$t" in
        '>'|'>>'|'<'|'2>'|'1>'|'&>')
          if (( ${#ARGS[@]} > 0 )) && ! is_redirect_token "${ARGS[0]}"; then
            shift_arg
          fi
          ;;
      esac
      continue
    fi
    kind=$(token_kind "$t")
    case "$kind" in
      end)
        if [[ "$stop_after_first" == 1 && count -eq 0 && ${#ARGS[@]} -gt 0 ]]; then
          printf '%s\n' "${ARGS[0]}" >>"$out"
        fi
        break
        ;;
      flag-value)
        shift_arg
        ;;
      flag) ;;
      arg)
        printf '%s\n' "$t" >>"$out"
        count=$((count + 1))
        if [[ "$stop_after_first" == 1 ]]; then
          break
        fi
        ;;
    esac
  done
}

parse_npx_like() {
  local mode_review=$1
  local positional=""
  local -a packages=()
  VALUE_FLAGS="-p --package -c --call --cache --userconfig --registry --npm --node-arg --node-options --cwd --prefix --package-manager"
  local t kind
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    shift_arg
    if is_redirect_token "$t"; then
      continue
    fi
    if [[ "$t" == "-p" || "$t" == "--package" || "$t" == "--with" || "$t" == "--from" ]]; then
      if (( ${#ARGS[@]} > 0 )); then
        packages+=("${ARGS[0]}")
        shift_arg
      fi
      continue
    fi
    case "$t" in
      --package=*|--with=*|--from=*)
        packages+=("${t#*=}")
        continue
        ;;
    esac
    kind=$(token_kind "$t")
    case "$kind" in
      end)
        if [[ -z "$positional" && ${#packages[@]} -eq 0 && ${#ARGS[@]} -gt 0 ]]; then
          positional=${ARGS[0]}
        fi
        break
        ;;
      flag-value) shift_arg ;;
      flag) ;;
      arg)
        if [[ -z "$positional" ]]; then
          positional=$t
        else
          break
        fi
        ;;
    esac
  done
  local p
  if (( ${#packages[@]} > 0 )); then
    for p in "${packages[@]}"; do
      queue_npm_spec "$p" execute "$mode_review"
    done
  elif [[ -n "$positional" ]]; then
    queue_npm_spec "$positional" execute "$mode_review"
  fi
}

parse_js_pm() {
  local pm=$1
  local verb="" t kind review=review
  case "$pm" in
    npm)
      VALUE_FLAGS="--prefix --userconfig --cache --registry --loglevel --script-shell --cwd --dir --workspace -w --omit --include --tag --globalconfig --cpu --os --libc --before --install-strategy"
      ;;
    pnpm)
      VALUE_FLAGS="--filter -F --dir -C --reporter --loglevel --registry --store-dir --config --prefix --package-import-method --reporter"
      ;;
    yarn)
      VALUE_FLAGS="--cwd --modules-folder --cache-folder --network-timeout --registry --focus --emoji"
      ;;
    bun)
      VALUE_FLAGS="--cwd --config --filter --backend --registry --origin"
      ;;
    *)
      VALUE_FLAGS="--prefix --cwd --registry --cache"
      ;;
  esac
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    if [[ "$t" == "--ignore-scripts" || "$t" == "--package-lock-only" ]]; then
      review=skip-review
    fi
    kind=$(token_kind "$t")
    if [[ "$kind" == arg ]]; then
      verb=$(lower "$t")
      shift_arg
      break
    elif [[ "$kind" == flag-value ]]; then
      shift_arg
      shift_arg
    elif [[ "$kind" == end ]]; then
      shift_arg
      break
    else
      shift_arg
    fi
  done
  case "$verb" in
    ci) return 0 ;;
    install|i|add|update|pack|remove|uninstall|un|rm|exec|dlx|x|create|init) ;;
    *) return 0 ;;
  esac
  case "$verb" in
    remove|uninstall|un|rm) return 0 ;;
  esac
  if [[ "$verb" == exec || "$verb" == dlx || "$verb" == x ]]; then
    if [[ "$verb" == exec && "$pm" != npm ]]; then
      return 0
    fi
    parse_npx_like "$review"
    return 0
  fi
  if [[ "$verb" == create || "$verb" == init ]]; then
    local init=""
    local pos="$WORKDIR/init.pos.$$"
    collect_positionals "$pos" 1
    if [[ -s "$pos" ]]; then
      IFS= read -r init <"$pos"
      case "$init" in
        ""| -y|--yes|-h|--help) return 0 ;;
        create-*) queue_npm_spec "$init" execute review ;;
        @*) queue_npm_spec "$init" execute review ;;
        *) queue_npm_spec "create-${init}" execute review ;;
      esac
    fi
    return 0
  fi
  local pos="$WORKDIR/js.pos.$$" spec count=0
  collect_positionals "$pos" 0
  if [[ -s "$pos" ]]; then
    while IFS= read -r spec || [[ -n "$spec" ]]; do
      [[ -z "$spec" ]] && continue
      queue_npm_spec "$spec" install "$review"
      count=$((count + 1))
    done <"$pos"
  fi
  if (( count == 0 )) && [[ "$verb" == install || "$verb" == i ]]; then
    queue_unlocked_npm_deps
  fi
}

queue_unlocked_npm_deps() {
  local root=$CWD pj names name lock_exists=0 count=0
  [[ -n "$root" && -f "$root/package.json" ]] || return 0
  if [[ -f "$root/package-lock.json" || -f "$root/pnpm-lock.yaml" || -f "$root/yarn.lock" || -f "$root/bun.lock" || -f "$root/npm-shrinkwrap.json" ]]; then
    lock_exists=1
  fi
  names=$(jq -r '[.dependencies,.devDependencies,.optionalDependencies] | .[]? | keys[]?' "$root/package.json" 2>/dev/null || true)
  local globs glob
  globs=$(jq -r 'if (.workspaces|type)=="array" then .workspaces[] elif (.workspaces.packages|type)=="array" then .workspaces.packages[] else empty end' "$root/package.json" 2>/dev/null || true)
  if [[ -n "$globs" ]]; then
    local shopt_state
    shopt_state=$(shopt -p nullglob || true)
    shopt -s nullglob
    while IFS= read -r glob; do
      [[ -z "$glob" ]] && continue
      for pj in "$root"/$glob/package.json; do
        [[ -f "$pj" ]] || continue
        names="${names}"$'\n'"$(jq -r '[.dependencies,.devDependencies,.optionalDependencies] | .[]? | keys[]?' "$pj" 2>/dev/null || true)"
      done
    done <<<"$globs"
    eval "$shopt_state" || true
  fi
  [[ -n "$names" ]] || return 0
  count=$(printf '%s\n' "$names" | grep -c . || true)
  if (( lock_exists == 0 && count > 40 )); then
    return 0
  fi
  local IFS=$'\n'
  for name in $names; do
    [[ -z "$name" ]] && continue
    if (( lock_exists == 1 )) && lock_has_npm_name "$root" "$name"; then
      continue
    fi
    add_check npm "$name" "" install review
  done
}

lock_has_npm_name() {
  local root=$1 name=$2 f esc
  esc=$(printf '%s' "$name" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g')
  for f in "$root/package-lock.json" "$root/npm-shrinkwrap.json" "$root/pnpm-lock.yaml" "$root/yarn.lock" "$root/bun.lock"; do
    [[ -f "$f" ]] || continue
    if grep -q -E "(node_modules/${esc}([/\"]|$)|(^|[/'\"[:space:]])${esc}@)" "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

pip_skip_value_flag() {
  case "$1" in
    -c|--constraint|-i|--index-url|--extra-index-url|-t|--target|-f|--find-links|--prefix|--root|--src|--config-settings|-C|--python|--implementation|--abi|--platform|--group|--package|--script|--optional|--bounds|--rev|--tag|--branch|--extra|--index|--default-index|--python-platform|--env-file|--constraints|--overrides|--build-constraints|--with-editable)
      return 0
      ;;
  esac
  return 1
}

queue_maybe_pypi() {
  local spec=$1 mode=$2
  [[ -z "$spec" ]] && return 0
  if is_local_spec "$spec"; then
    return 0
  fi
  if printf '%s' "$spec" | grep -q '://\|git+\|git@'; then
    note_url_spec "$spec"
    return 0
  fi
  queue_pypi_req "$spec" "$mode"
}

parse_pip_install() {
  local mode=$1 t flag val
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    shift_arg
    if is_redirect_token "$t"; then
      case "$t" in
        '>'|'>>'|'<'|'2>'|'1>'|'&>')
          if (( ${#ARGS[@]} > 0 )); then shift_arg; fi
          ;;
      esac
      continue
    fi
    case "$t" in
      -r|--requirement|--with-requirements)
        if (( ${#ARGS[@]} > 0 )); then
          queue_requirements_file "${ARGS[0]}" "$mode"
          shift_arg
        fi
        ;;
      --requirement=*|--with-requirements=*)
        queue_requirements_file "${t#*=}" "$mode"
        ;;
      -e|--editable)
        if (( ${#ARGS[@]} > 0 )); then
          queue_maybe_pypi "${ARGS[0]}" "$mode"
          shift_arg
        fi
        ;;
      --editable=*)
        queue_maybe_pypi "${t#*=}" "$mode"
        ;;
      --from|--with)
        if (( ${#ARGS[@]} > 0 )); then
          queue_pypi_req "${ARGS[0]}" "$mode"
          shift_arg
        fi
        ;;
      --from=*|--with=*)
        queue_pypi_req "${t#*=}" "$mode"
        ;;
      --*=*)
        flag=${t%%=*}
        pip_skip_value_flag "$flag" || queue_pypi_req "${t#*=}" "$mode"
        ;;
      -*)
        if pip_skip_value_flag "$t" && (( ${#ARGS[@]} > 0 )); then
          shift_arg
        fi
        ;;
      *)
        queue_pypi_req "$t" "$mode"
        ;;
    esac
  done
}

parse_python() {
  local module=""
  while (( ${#ARGS[@]} > 0 )); do
    case "${ARGS[0]}" in
      -m)
        shift_arg
        module=${ARGS[0]:-}
        shift_arg
        break
        ;;
      -*)
        shift_arg
        ;;
      *)
        return 0
        ;;
    esac
  done
  [[ "$module" == pip || "$module" == pip3 ]] || return 0
  if (( ${#ARGS[@]} == 0 )); then
    return 0
  fi
  local verb
  verb=$(lower "${ARGS[0]}")
  shift_arg
  case "$verb" in
    install|download) parse_pip_install install ;;
  esac
}

parse_uv() {
  local bin=$1
  if [[ "$bin" == uvx ]]; then
    parse_uvx
    return
  fi
  local verb=""
  verb=$(lower "${ARGS[0]:-}")
  shift_arg
  case "$verb" in
    add)
      parse_pip_install install
      ;;
    pip)
      local sub
      sub=$(lower "${ARGS[0]:-}")
      shift_arg
      case "$sub" in
        install|download) parse_pip_install install ;;
      esac
      ;;
    tool)
      local sub
      sub=$(lower "${ARGS[0]:-}")
      shift_arg
      case "$sub" in
        install) parse_pip_install install ;;
        run) parse_uvx ;;
      esac
      ;;
    sync|lock|pip)
      ;;
  esac
}

parse_uvx() {
  local has_from=0 positional="" t
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    shift_arg
    case "$t" in
      --from)
        has_from=1
        if (( ${#ARGS[@]} > 0 )); then
          queue_pypi_req "${ARGS[0]}" execute
          shift_arg
        fi
        ;;
      --from=*)
        has_from=1
        queue_pypi_req "${t#*=}" execute
        ;;
      --with|-w)
        if (( ${#ARGS[@]} > 0 )); then
          queue_pypi_req "${ARGS[0]}" execute
          shift_arg
        fi
        ;;
      --with=*)
        queue_pypi_req "${t#*=}" execute
        ;;
      --with-requirements)
        if (( ${#ARGS[@]} > 0 )); then
          queue_requirements_file "${ARGS[0]}" execute
          shift_arg
        fi
        ;;
      --with-requirements=*)
        queue_requirements_file "${t#*=}" execute
        ;;
      --with-editable)
        if (( ${#ARGS[@]} > 0 )); then
          queue_maybe_pypi "${ARGS[0]}" execute
          shift_arg
        fi
        ;;
      --python|--index|--index-url|--extra-index-url|--find-links|--python-platform|--env-file|--constraints|--overrides|--build-constraints|-c|-b)
        if (( ${#ARGS[@]} > 0 )); then shift_arg; fi
        ;;
      --*=*) ;;
      -*) ;;
      *)
        if [[ -z "$positional" ]]; then
          positional=$t
        else
          break
        fi
        ;;
    esac
  done
  if (( has_from == 0 )) && [[ -n "$positional" ]]; then
    queue_pypi_req "$positional" execute
  fi
}

parse_cargo() {
  local verb
  verb=$(lower "${ARGS[0]:-}")
  shift_arg
  case "$verb" in
    install|add) ;;
    *) return 0 ;;
  esac
  local saw_path=0 saw_git=0 t
  local -a crates=()
  while (( ${#ARGS[@]} > 0 )); do
    t=${ARGS[0]}
    shift_arg
    case "$t" in
      --git)
        saw_git=1
        if (( ${#ARGS[@]} > 0 )); then
          note_url_spec "${ARGS[0]}"
          shift_arg
        fi
        ;;
      --git=*)
        saw_git=1
        note_url_spec "${t#*=}"
        ;;
      --path|--path=*)
        saw_path=1
        if [[ "$t" == --path ]] && (( ${#ARGS[@]} > 0 )); then shift_arg; fi
        ;;
      --version|--branch|--tag|--rev|--bin|--example|--features|--manifest-path|--target|--profile|--registry|--index|--config|--package|-p|-Z)
        if (( ${#ARGS[@]} > 0 )); then shift_arg; fi
        ;;
      --*=*) ;;
      -*) ;;
      *)
        crates+=("$t")
        ;;
    esac
  done
  if (( saw_path == 1 || saw_git == 1 )); then
    return 0
  fi
  if (( ${#crates[@]} > 0 )); then
    local crate
    for crate in "${crates[@]}"; do
      is_local_spec "$crate" && continue
      add_check cargo "$crate" "" install skip-review
    done
  fi
}

parse_gem() {
  local verb
  verb=$(lower "${ARGS[0]:-}")
  shift_arg
  [[ "$verb" == install ]] || return 0
  VALUE_FLAGS="-v --version --source -s --bindir --document -n --conservative --platform --install-dir"
  local pos="$WORKDIR/gem.pos.$$" line
  collect_positionals "$pos" 0
  if [[ -s "$pos" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      add_check gem "$line" "" install skip-review
    done <"$pos"
  fi
}

parse_go() {
  local verb
  verb=$(lower "${ARGS[0]:-}")
  shift_arg
  [[ "$verb" == install ]] || return 0
  VALUE_FLAGS=""
  local pos="$WORKDIR/go.pos.$$" line
  collect_positionals "$pos" 0
  if [[ -s "$pos" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      case "$line" in
        -*) continue ;;
        std|cmd|cmd/*) continue ;;
      esac
      add_check go "$line" "" install skip-review
    done <"$pos"
  fi
}

parse_composer() {
  local verb
  while (( ${#ARGS[@]} > 0 )); do
    case "${ARGS[0]}" in
      -*) shift_arg ;;
      *) verb=$(lower "${ARGS[0]}"); shift_arg; break ;;
    esac
  done
  case "$verb" in
    require|update) ;;
    *) return 0 ;;
  esac
  [[ "$verb" == update ]] && return 0
  VALUE_FLAGS="--working-dir -d --ignore-platform-req --with --sort-packages"
  local pos="$WORKDIR/composer.pos.$$" line
  collect_positionals "$pos" 0
  if [[ -s "$pos" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      line=${line%%:*}
      add_check composer "$line" "" install skip-review
    done <"$pos"
  fi
}

parse_dotnet() {
  local a1 a2
  a1=$(lower "${ARGS[0]:-}")
  shift_arg
  if [[ "$a1" == tool ]]; then
    a2=$(lower "${ARGS[0]:-}")
    shift_arg
    [[ "$a2" == install || "$a2" == update ]] || return 0
    VALUE_FLAGS="--version -v --framework --source --configfile --tool-path --verbosity --add-source"
    local pos="$WORKDIR/dotnet.pos.$$" line
    collect_positionals "$pos" 1
    if [[ -s "$pos" ]]; then
      IFS= read -r line <"$pos"
      [[ "$line" == -* || -z "$line" ]] && return 0
      add_check nuget "$line" "" install skip-review
    fi
    return 0
  fi
  if [[ "$a1" == add ]]; then
    local kind=""
    while (( ${#ARGS[@]} > 0 )); do
      case "${ARGS[0]}" in
        package|Package)
          kind=package
          shift_arg
          break
          ;;
        -*) shift_arg ;;
        *) shift_arg ;;
      esac
    done
    [[ "$kind" == package ]] || return 0
    VALUE_FLAGS="--version -v --source --framework -f --package-directory --interactive --prerelease"
    local pos="$WORKDIR/dotnet.pkg.$$" line
    collect_positionals "$pos" 1
    if [[ -s "$pos" ]]; then
      IFS= read -r line <"$pos"
      [[ -z "$line" ]] && return 0
      add_check nuget "$line" "" install skip-review
    fi
  fi
}

parse_brew() {
  local verb kind=formula
  while (( ${#ARGS[@]} > 0 )); do
    case "${ARGS[0]}" in
      --cask) kind=cask; shift_arg ;;
      --formula) kind=formula; shift_arg ;;
      -*) shift_arg ;;
      *) verb=$(lower "${ARGS[0]}"); shift_arg; break ;;
    esac
  done
  [[ "$verb" == install || "$verb" == upgrade ]] || return 0
  [[ "$verb" == upgrade ]] && (( ${#ARGS[@]} == 0 )) && return 0
  VALUE_FLAGS="--appdir --fontdir --debug"
  local pos="$WORKDIR/brew.pos.$$" line
  while (( ${#ARGS[@]} > 0 )); do
    case "${ARGS[0]}" in
      --cask) kind=cask; shift_arg ;;
      --formula) kind=formula; shift_arg ;;
      *) break ;;
    esac
  done
  collect_positionals "$pos" 0
  if [[ -s "$pos" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      add_check brew "$line" "$kind" install skip-review
    done <"$pos"
  fi
}

parse_pip_bin() {
  local verb
  while (( ${#ARGS[@]} > 0 )); do
    case "${ARGS[0]}" in
      -*) shift_arg ;;
      *) verb=$(lower "${ARGS[0]}"); shift_arg; break ;;
    esac
  done
  case "$verb" in
    install|download) parse_pip_install install ;;
    run)
      # pipx run
      parse_uvx
      ;;
  esac
}

inspect_segment() {
  (( DEPTH > 4 )) && return 0
  set_args_from_line "$1"
  strip_wrappers
  (( ${#ARGS[@]} > 0 )) || return 0
  local rawbin bin
  rawbin=${ARGS[0]}
  shift_arg
  bin=$(basename "$rawbin")
  bin=${bin%.cmd}
  bin=$(lower "$bin")
  if [[ "$bin" == cd ]]; then
    local dest=${ARGS[0]:-}
    [[ -z "$dest" || "$dest" == -* ]] && return 0
    case "$dest" in
      /*) CWD=$dest ;;
      ~/*) CWD="${HOME}/${dest#~/}" ;;
      *) CWD=$(cd "$CWD" && cd "$dest" && pwd) || CWD="${CWD%/}/$dest" ;;
    esac
    return 0
  fi
  case "$bin" in
    bash|sh|zsh|dash)
      local script="" t
      while (( ${#ARGS[@]} > 0 )); do
        t=${ARGS[0]}
        shift_arg
        if [[ "$t" == "-c" || "$t" == "--command" || ( "$t" == -* && "$t" == *c* && "$t" != --* ) ]]; then
          script=${ARGS[0]:-}
          break
        fi
        if [[ "$t" != -* ]]; then
          break
        fi
      done
      if [[ -n "$script" ]]; then
        local saved=$DEPTH
        DEPTH=$((DEPTH + 1))
        process_command "$script"
        DEPTH=$saved
      fi
      ;;
    eval)
      if (( ${#ARGS[@]} > 0 )); then
        local saved=$DEPTH
        DEPTH=$((DEPTH + 1))
        process_command "${ARGS[0]}"
        DEPTH=$saved
      fi
      ;;
    corepack)
      if (( ${#ARGS[@]} > 0 )); then
        local inner
        inner=$(lower "${ARGS[0]}")
        case "$inner" in
          npm|pnpm|yarn)
            shift_arg
            parse_js_pm "$inner"
            ;;
        esac
      fi
      ;;
    npm|pnpm|yarn|bun) parse_js_pm "$bin" ;;
    npx|bunx) parse_npx_like review ;;
    pip|pip3) parse_pip_bin ;;
    pipx) parse_pip_bin ;;
    python|python3) parse_python ;;
    uv|uvx) parse_uv "$bin" ;;
    cargo) parse_cargo ;;
    gem) parse_gem ;;
    go) parse_go ;;
    composer|composer.phar) parse_composer ;;
    dotnet) parse_dotnet ;;
    brew) parse_brew ;;
  esac
}

split_segments() {
  local s=$1 out=$2
  : >"$out"
  local cur="" quote="" i c n
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ -n "$quote" ]]; then
      cur="${cur}${c}"
      if [[ "$c" == "$quote" ]]; then
        quote=""
      fi
      continue
    fi
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      quote=$c
      cur="${cur}${c}"
      continue
    fi
    if [[ "$c" == $'\n' || "$c" == ';' ]]; then
      printf '%s\n' "$cur" >>"$out"
      cur=""
      continue
    fi
    if [[ "$c" == '|' || "$c" == '&' ]]; then
      n=${s:i+1:1}
      if [[ "$n" == "$c" ]]; then
        printf '%s\n' "$cur" >>"$out"
        cur=""
        i=$((i + 1))
        continue
      fi
      if [[ "$c" == '|' ]]; then
        printf '%s\n' "$cur" >>"$out"
        cur=""
        continue
      fi
    fi
    cur="${cur}${c}"
  done
  printf '%s\n' "$cur" >>"$out"
}

process_command() {
  local s=$1 segfile="$WORKDIR/segs.$RANDOM" line
  split_segments "$s" "$segfile"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    [[ -z "$line" ]] && continue
    inspect_segment "$line"
  done <"$segfile"
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    echo >&2 "ai-coding-hooks: validate-package-install.sh requires jq on PATH"
    echo "{}"
    exit 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo >&2 "ai-coding-hooks: validate-package-install.sh requires curl on PATH"
    echo "{}"
    exit 0
  fi

  INPUT=$(cat)
  local cmd
  cmd=$(jq -r '.command // .tool_input.command // ""' <<<"$INPUT")
  CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
  [[ -n "$CWD" ]] || CWD=$PWD
  if [[ -z "${cmd//[[:space:]]/}" ]]; then
    allow_out
    exit 0
  fi

  WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/pkg-trust.XXXXXX")
  CACHE_DIR="${TMPDIR:-/tmp}/claude-package-trust"
  mkdir -p "$CACHE_DIR"
  : >"$WORKDIR/checks"
  trap 'rm -rf "$WORKDIR"' EXIT

  process_command "$cmd"
  if [[ -s "$WORKDIR/checks" ]]; then
    run_checks
  fi
  if [[ -n "$REASONS" ]]; then
    deny_out "$REASONS"
    exit 0
  fi
  allow_out
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
