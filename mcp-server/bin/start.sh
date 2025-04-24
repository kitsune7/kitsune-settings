#!/usr/bin/env bash

# Install node_modules if not already installed
if [ ! -d "$SETTINGS_DIR/mcp-server/node_modules" ]; then
  npm --prefix $SETTINGS_DIR/mcp-server install
fi

# Build the MCP server
npm --prefix $SETTINGS_DIR/mcp-server run build

# Start the MCP server
node $SETTINGS_DIR/mcp-server/dist/index.js
