oriServerPort=1230

alias ori-server="${SETTINGS_DIR}/custom-scripts/ori/ori.py"
alias os="ori-server"

function ori () {
  (ori-server > /dev/null 2>&1 &)
  sleep 1

  response=$(curl -s -X POST http://localhost:1230/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "qwen2.5-7b-instruct-1m",
      "messages": [
        {
          "role": "user",
          "content": "'$1'"
        }
      ]
    }')
  curl_exit_code=$?

  if [ $curl_exit_code -ne 0 ]; then
    echo "Ori failed to start or respond appropriately."
    exit 1
  else
    echo $response | jq -Rnr '[inputs] | join("\\n") | fromjson | .choices[0].message.content'
  fi

  sleep 3
  kill -9 $(lsof -t -i tcp:${oriServerPort})
}