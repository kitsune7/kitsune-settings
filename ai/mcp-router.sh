#!/usr/bin/env bash

# This script is used to run the appropriate MCP server. Using a script allows us to use env
# variables instead of hard-coding sensitive information like API keys.

# The script takes a single argument, which is the name of the server to route the request to.

if [ -z "$1" ]; then
  echo "Usage: $0 <server-name>"
  exit 1
fi

case "$1" in
  "kitsune-mcp")
    "$SETTINGS_DIR/mcp-server/bin/start.sh"
    ;;
  "github")
    echo "Github token: $GITHUB_PERSONAL_ACCESS_TOKEN"
    docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN=$GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
    ;;
  "mcp-atlassian")
    docker run -i --rm -e JIRA_URL=$JIRA_URL -e JIRA_USERNAME=$JIRA_USERNAME -e JIRA_API_TOKEN=$JIRA_API_TOKEN -e JIRA_PROJECTS_FILTER=$JIRA_PROJECTS_FILTER ghcr.io/sooperset/mcp-atlassian:latest
    ;;
  *)
    echo "Server \"$1\" hasn't been added to $SETTINGS_DIR/ai/mcp-router.sh"
    exit 1
esac
