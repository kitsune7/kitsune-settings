alias ori-server="${SETTINGS_DIR}/custom-scripts/ori.py"
alias os="ori-server"

function ori () {
  ori-server > /dev/null & server_pid=$!
  sleep 1
  curl -X POST http://localhost:1230/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "qwen2.5-7b-instruct-1m",
      "messages": [
        {
          "role": "user",
          "content": "'$1'"
        }
      ]
    }' | jq -r '.completions[0].message.content'
  curl_exit_code=$?
  kill $server_pid
  if [ $curl_exit_code -ne 0 ]; then
    echo "Ori failed to start or respond appropriately."
    exit 1
  else
    echo $response | jq -r '.completions[0].message.content'
  fi
}