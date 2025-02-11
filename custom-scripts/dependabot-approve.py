#!/usr/bin/env uv run --script
# /// script
# requires-python = ">=3.12"
# ///

import subprocess
import json
import re
import argparse

def determine_update_type(version_string):
  """
  Determines if the change between two semver versions in a string is 
  a major, minor, or patch update.

  Args:
      version_string (str): A string containing text followed by "from X.Y.Z to A.B.C".

  Returns:
      str: "major", "minor", "patch", or "no change" depending on the update type.
  """
  # Extract versions using regex
  match = re.search(r"from (\d+\.\d+\.\d+) to (\d+\.\d+\.\d+)", version_string)
  
  if not match:
    raise ValueError("Input string does not contain valid 'from' and 'to' semver versions.")
  
  # Parse the versions
  version_1 = list(map(int, match.group(1).split('.')))
  version_2 = list(map(int, match.group(2).split('.')))
  
  # Compare versions to determine update type
  if version_1[0] != version_2[0]:
    return "major"
  elif version_1[1] != version_2[1]:
    return "minor"
  elif version_1[2] != version_2[2]:
    return "patch"
  else:
    return "no change"

parser = argparse.ArgumentParser("dependabot-approve", description="Approve low-risk dependabot PRs.")
parser.add_argument('user_or_org', help="The user/org that owns the repo")
parser.add_argument('repo', help="The repo to check PRs for")
args = parser.parse_args()
repo = f"{args.user_or_org}/{args.repo}"

# Fetch all open Dependabot PRs
pr_list_command = f"gh pr list --repo {repo} --search 'author:app/dependabot' --json number,title,headRefName,mergeable,reviews"
pr_list_result = subprocess.run(pr_list_command, shell=True, capture_output=True, text=True)

try:
  pr_list = json.loads(pr_list_result.stdout)
except json.JSONDecodeError:
  print(f'{pr_list_result.stderr}\n')
  print("Error: Unable to fetch PR list.")
  exit(1)

eligible_prs = []

for pr in pr_list:
  pr_number = pr['number']
  pr_title = pr['title']
  mergeable = pr['mergeable']
  reviews = pr['reviews']

  # Skip if the PR is already approved
  already_approved = any(review['state'] == 'APPROVED' for review in reviews)
  if already_approved:
    print(f"PR #{pr_number} is already approved. Skipping.")
    continue

  # Ensure all status checks are passing
  if mergeable != "MERGEABLE":
    print(f"PR #{pr_number} does not have all status checks passing. Skipping.")
    continue

  # Ensure it's not a major version bump
  try:
    update_type = determine_update_type(pr_title)
    if update_type == "major":
      print(f"PR #{pr_number} is a major version bump. Skipping.")
      continue
    elif update_type == "no change":
      print(f"PR #{pr_number} does not change the version. Skipping.")
      continue
  except ValueError as e:
    print(f"Error determining update type for PR #{pr_number}: {e}")
    continue

  eligible_prs.append((pr_number, pr_title))

if not eligible_prs:
  print("No eligible PRs found for approval.")
  exit(0)

print("\nThe following PRs are eligible for approval:")
for pr_number, pr_title in eligible_prs:
  print(f"PR #{pr_number}: {pr_title}")

response = input("\nWould you like to approve these PRs? (y/N): ")
if response.lower() != 'y':
  print("Operation cancelled.")
  exit(0)

for pr_number, pr_title in eligible_prs:
  approve_command = f"gh pr review {pr_number} --repo {repo} --approve"
  subprocess.run(approve_command, shell=True)
  print(f"Approved PR #{pr_number}: {pr_title}")
