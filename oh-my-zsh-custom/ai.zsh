oriServerPort=1230

alias ori-server="${SETTINGS_DIR}/custom-scripts/ori.py"
alias os="ori-server"

function ori () {
  (ori-server > /dev/null 2>&1 &)

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
  kill -9 $(lsof -t -i tcp:${oriServerPort})

  if [ $curl_exit_code -ne 0 ]; then
    echo "Ori failed to start or respond appropriately."
    exit 1
  else
    echo $response | jq -r '.choices[0].message.content'
  fi
}