alias ori-server="${SETTINGS_DIR}/custom-scripts/ori.py"
alias os="ori-server"

function ori () {
  ori-server & server_pid=$!
  sleep 1
  curl -f http://localhost:1230
  curl_exit_code=$?
  kill $server_pid
  if [ $curl_exit_code -ne 0 ]; then
    echo "Server failed to start and accept connections"
  fi
}