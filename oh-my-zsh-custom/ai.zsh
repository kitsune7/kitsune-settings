oriServerPort=1230

alias os="ori-start"

function ori-start () {
  ${SETTINGS_DIR}/custom-scripts/ori/ori.py
}

function ori-stop () {
  kill -9 $(lsof -t -i tcp:$oriServerPort)
}

function ori () {
  if [ ! $(lsof -i tcp:$oriServerPort) ]; then
    (ori-start > /dev/null &)
    sleep 1
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
    return 1
  elif [ $(echo $response | jq -r '.error') != "null" ]; then
    echo $response | jq -r '.error'
    return 1
  else
    echo $response | jq -Rnr '[inputs] | join("\\n") | fromjson | .choices[0].message.content'
  fi
}
