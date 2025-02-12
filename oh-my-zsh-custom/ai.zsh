oriServerPort=1230

alias os="ori-start"

function ori-start () {
  bun "${SETTINGS_DIR}/custom-scripts/ori/ori.ts"
}

function ori-stop () {
  if ! lsof -i tcp:$oriServerPort >/dev/null 2>&1; then
    echo "Ori is not running."
    return 1
  fi
  kill -9 $(lsof -t -i tcp:$oriServerPort)
  echo "Ori has been stopped."
}

function ori () {
  if ! lsof -i tcp:$oriServerPort >/dev/null 2>&1; then
    (ori-start > /dev/null &)
    sleep 1
  fi

  local input_text=$(printf '%s' "$*" | sed 's/"/\\"/g')
  
  response=$(curl -s -X POST http://localhost:1230/chat/completions \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"qwen2.5-7b-instruct-1m\",
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"$input_text\"
        }
      ]
    }")
  curl_exit_code=$?

  if [ $curl_exit_code -ne 0 ]; then
    echo "Ori failed to start or respond appropriately."
    return 1
  elif [ $(echo $response | jq -Rnr '[inputs] | join("\\n") | fromjson | .error') != "null" ]; then
    echo $response | jq -Rnr '[inputs] | join("\\n") | fromjson | .error'
    return 1
  else
    echo $response | jq -Rnr '[inputs] | join("\\n") | fromjson | .choices[0].message.content'
  fi
}
