#!/usr/bin/env uv run --script
# /// script
# requires-python = ">=3.12"
# ///

import subprocess
import json
import os
import sys

def get_all_notifications():
    """Gets all GitHub notifications."""
    print("Fetching all GitHub notifications...")
    cmd = "gh api /notifications"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print("Error fetching notifications:")
        print(result.stderr)
        return []
    try:
        notifications = json.loads(result.stdout)
        print(f"Found {len(notifications)} notifications.")
        return notifications
    except json.JSONDecodeError:
        print("Error parsing notifications JSON.")
        return []

def get_pr_details(pr_api_path):
    """Gets details for a specific PR using its API path."""
    cmd = f"gh api {pr_api_path}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error fetching PR details from {pr_api_path}:\n{result.stderr}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

def mark_notification_as_done(thread_id):
  """
  Marks a notification thread as done.
  
  Args:
    thread_id (str): The ID of the notification thread.
  
  Returns:
    bool: True if successfully marked as done, False otherwise.
  """
  cmd = f"gh api -X DELETE /notifications/threads/{thread_id}"
  result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
  return result.returncode == 0

def main():
    """
    Main function to process notifications and run approval script.
    """
    notifications = get_all_notifications()
    if not notifications:
        print("No notifications to process.")
        return

    repos_to_check = set()
    
    for notification in notifications:
        if notification.get('subject', {}).get('type') != 'PullRequest':
            continue

        pr_api_url = notification.get('subject', {}).get('url')
        if not pr_api_url:
            continue
        
        pr_api_path = pr_api_url.replace("https://api.github.com", "")
        pr_details = get_pr_details(pr_api_path)

        if not pr_details:
            print(f"Could not fetch details for PR related to notification {notification['id']}")
            continue
            
        is_dependabot_pr = pr_details.get('user', {}).get('login') == 'dependabot[bot]'
        repo_full_name = notification['repository']['full_name']

        if pr_details['state'] == 'closed':
            print(f"PR #{pr_details['number']} in {repo_full_name} is closed/merged. Marking notification as done.")
            if mark_notification_as_done(notification['id']):
                print(f"  Successfully marked notification {notification['id']} as done.")
            else:
                print(f"  Failed to mark notification {notification['id']} as done.")
            continue
            
        if is_dependabot_pr and pr_details['state'] == 'open':
            repos_to_check.add(repo_full_name)

    if not repos_to_check:
        print("\nNo open Dependabot PRs found in notifications that require action.")
        return

    print("\nFound open Dependabot PRs in the following repos:")
    for repo in sorted(list(repos_to_check)):
        print(f"- {repo}")

    script_dir = os.path.dirname(os.path.realpath(__file__))
    approve_script_path = os.path.join(script_dir, 'dependabot-approve.py')

    for repo in sorted(list(repos_to_check)):
        owner, repo_name = repo.split('/')
        print(f"\n--- Running dependabot-approve for {repo} ---")
        cmd = [approve_script_path, owner, repo_name]
        
        with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, universal_newlines=True) as process:
            for line in process.stdout:
                sys.stdout.write(line)
        
        print(f"--- Finished dependabot-approve for {repo} ---")

if __name__ == "__main__":
    main() 