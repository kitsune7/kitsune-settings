function go-latest() {
  download_page=$(curl -sL "https://go.dev/dl/?mode=json")
  latest_version=$(echo "$download_page" | jq -r '.[0].version')

  if [[ -z "$latest_version" ]]; then
    echo "Error: Failed to retrieve latest Go version."
  else
    echo $latest_version
  fi
}
