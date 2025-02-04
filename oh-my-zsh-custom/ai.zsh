oriServerPort=1230

alias ori-start="${SETTINGS_DIR}/custom-scripts/ori/ori.py"
alias ori-start-quiet="ori-start > /dev/null 2>&1 &"
alias ori-stop="kill -9 $(lsof -t -i tcp:$oriServerPort)"
alias os="ori-start"

alias 

function ori () {
  if [ ! $(lsof -i tcp:$oriServerPort) ]; then
    ori-start-quiet
  fi

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
}