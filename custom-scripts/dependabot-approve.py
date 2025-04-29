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

def parse_dependency_table(body):
  """
  Parses the dependency table from a PR description and returns a list of
  dictionaries containing package info and version changes.

  Args:
      body (str): The PR description containing the markdown table.

  Returns:
      list: List of dictionaries with package info and version changes.
  """
  dependencies = []
  
  # Find the table in the description
  table_lines = []
  in_table = False
  for line in body.split('\n'):
    if '|' in line:
      if '---' in line:  # Skip the header separator
        continue
      if 'Package' in line:  # Skip the header
        continue
      table_lines.append(line.strip())
  
  # Parse each row of the table
  for line in table_lines:
    # Split the line into columns and clean up
    columns = [col.strip() for col in line.split('|')[1:-1]]
    if len(columns) != 3:
      continue
    
    package_info = {
      'name': re.search(r'\[(.*?)\]', columns[0]).group(1) if '[' in columns[0] else columns[0],
      'from_version': columns[1].strip('`'),
      'to_version': columns[2].strip('`')
    }
    dependencies.append(package_info)
  
  return dependencies

def check_group_update_eligibility(dependencies):
  """
  Checks if all dependencies in a group update are eligible for approval.

  Args:
      dependencies (list): List of dictionaries containing package info and version changes.

  Returns:
      bool: True if all updates are minor or patch, False if any are major.
  """
  for dep in dependencies:
    version_string = f"from {dep['from_version']} to {dep['to_version']}"
    try:
      update_type = determine_update_type(version_string)
      if update_type == "major":
        return False
    except ValueError as e:
      print(f"Error determining update type for {dep['name']}: {e}")
      return False
  return True

parser = argparse.ArgumentParser("dependabot-approve", description="Approve low-risk dependabot PRs.")
parser.add_argument('user_or_org', help="The user/org that owns the repo")
parser.add_argument('repo', help="The repo to check PRs for")
args = parser.parse_args()
repo = f"{args.user_or_org}/{args.repo}"

# Fetch all open Dependabot PRs
pr_list_command = f"gh pr list --repo {repo} --search 'author:app/dependabot' --json number,title,headRefName,mergeable,reviews,body"
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
  pr_body = pr['body']
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

  # Check if this is a group update
  is_group_update = 'group' in pr_title.lower()
  
  if is_group_update:
    # Parse the dependency table and check all updates
    dependencies = parse_dependency_table(pr_body)
    if not dependencies:
      print(f"PR #{pr_number} is a group update but couldn't parse dependency table. Skipping.")
      continue
    
    if check_group_update_eligibility(dependencies):
      eligible_prs.append((pr_number, pr_title))
    else:
      print(f"PR #{pr_number} contains major version updates in group. Skipping.")
  else:
    # Handle single dependency update
    try:
      update_type = determine_update_type(pr_title)
      if update_type == "major":
        print(f"PR #{pr_number} is a major version bump. Skipping.")
        continue
      elif update_type == "no change":
        print(f"PR #{pr_number} does not change the version. Skipping.")
        continue
      eligible_prs.append((pr_number, pr_title))
    except ValueError as e:
      print(f"Error determining update type for PR #{pr_number}: {e}")
      continue

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
