#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "flask",
#     "requests",
# ]
# ///

import subprocess
import requests
import os
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

tool_schemas = []
for fname in os.listdir("tools"):
    with open(f"tools/{fname}") as f:
        tool_schemas.append(json.load(f))

LM_STUDIO_URL = "http://localhost:1234/v1"

def start_lm_studio():
    try:
        subprocess.run(["lms", "server", "start"], check=True)
        print("LM Studio server started successfully")
    except subprocess.CalledProcessError:
        print("Failed to start LM Studio server")

def load_model():
    try:
        subprocess.run(["lms", "model", "load", "--first"], check=True)
        print("Model loaded successfully")
    except subprocess.CalledProcessError:
        print("Failed to load model")

def check_lm_studio_status():
    try:
        response = requests.get(f"{LM_STUDIO_URL}/models")
        if response.status_code == 200:
            return True
        return False
    except requests.RequestException:
        return False

def execute_tool(tool_name, tool_args):
    tool_name_to_function = {
        "create_note": create_note,
    }
    if tool_name in tool_name_to_function:
        return tool_name_to_function[tool_name](tool_args)
    else:
        return f"Unknown tool: {tool_name}"

def create_note(tool_args):
    return f"Create note with tool_args: {tool_args}"

@app.route('/<path:subpath>', methods=['POST'])
def proxy(subpath):
    if not check_lm_studio_status():
        start_lm_studio()
        load_model()

    url = f"{LM_STUDIO_URL}/{subpath}"
    response = requests.post(url, json={**request.json, "tools": tool_schemas})

    if response.status_code == 200:
        content = response.json()
        if "tool_calls" in content:
            for tool_call in content["tool_calls"]:
                tool_name = tool_call["function"]["name"]
                tool_args = json.loads(tool_call["function"]["arguments"])
                tool_result = execute_tool(tool_name, tool_args)
                content["tool_results"] = tool_result
        return jsonify(content)
    else:
        return response.text, response.status_code

if __name__ == '__main__':
    app.run(port=1230)
