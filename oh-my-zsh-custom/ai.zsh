alias ori-server="${SETTINGS_DIR}/custom-scripts/ori.py"
alias os="ori-server"

function ori () {
  ori-server & server_pid=$!
  sleep 1
  curl -X POST http://localhost:1230/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "messages": [
        {
          "role": "user",
          "text": "'$1'"
        }
      ],
    }'
  curl_exit_code=$?
  kill $server_pid
  if [ $curl_exit_code -ne 0 ]; then
    echo "Ori failed to start or respond appropriately."
  fi
}