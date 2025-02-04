#!/usr/bin/env uv run --script
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
script_dir = os.path.dirname(os.path.abspath(__file__))
for fname in os.listdir(f"{script_dir}/tools"):
    with open(f"{script_dir}/tools/{fname}") as f:
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
    work_notes_path = os.environ.get("ICLOUD_WORK_NOTES_DIR", "")
    intermediate_path = "5 - Unsorted"
    if not work_notes_path:
        return {
            "error": "ICLOUD_WORK_NOTES_DIR environment variable is not set",
            "content": "",
        }
    note_name = tool_args.get("note_name", "Untitled Ori Note")
    note_content = tool_args.get("note_content", "")
    note_path = f"{work_notes_path}/{intermediate_path}/{note_name}.md"

    # Create the file for the note if it doesn't already exist
    if not os.path.exists(note_path):
        with open(note_path, "w") as f:
            f.write(note_content)

    return {
        "error": "",
        "content": f"Created note successfully: {intermediate_path}/{note_name}.md",
    }

@app.route('/<path:subpath>', methods=['POST'])
def proxy(subpath):
    if not check_lm_studio_status():
        start_lm_studio()
        load_model()

    url = f"{LM_STUDIO_URL}/{subpath}"
    response = requests.post(url, json={**request.json, "tools": tool_schemas})

    if response.status_code == 200:
        content = response.json()
        if "tool_calls" in content["choices"][0]["message"]:
            for tool_call in content["choices"][0]["message"]["tool_calls"]:
                tool_name = tool_call["function"]["name"]
                tool_args = json.loads(tool_call["function"]["arguments"])
                tool_result = execute_tool(tool_name, tool_args)
                if tool_result.get("error"):
                    response.status_code = 500
                    content["error"] = tool_result["error"]
                content["tool_results"] = tool_result.get("content", "")
        return jsonify(content)
    else:
        return response.text, response.status_code

if __name__ == '__main__':
    app.run(port=1230)
