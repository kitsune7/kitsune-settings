---
name: fix-pr-comments
description: "Pulls down all comments for a given PR URL using the GitHub CLI, finds unresolved concerns, validates they are real issues, and fixes them."
---

# Fix PR Comments

## Overview

Resolve unresolved PR review comments by pulling them down via the GitHub CLI, validating each concern, and implementing fixes for legitimate issues. This skill focuses on actionable review feedback — not resolved threads, not praise, and not trivial nits unless specifically requested.

## Input

The user provides a GitHub PR URL as an argument, e.g.:

```
/fix-pr-comments https://github.com/owner/repo/pull/1234
```

If no URL is provided, ask the user for one.

## Workflow

### 1. Parse the PR URL

Extract the owner, repo, and PR number from the URL. Supported formats:

- `https://github.com/{owner}/{repo}/pull/{number}`
- `{owner}/{repo}#{number}`
- Just a PR number (infer owner/repo from the current git remote)

### 2. Fetch PR metadata

Run the following to understand the PR context:

```bash
gh pr view <URL> --json title,body,headRefName,baseRefName,files
```

This gives you the PR title, description, branch names, and changed files so you understand the scope.

### 3. Fetch all review threads via GraphQL

Use the GitHub GraphQL API to get all review threads with their resolved status:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          startLine
          comments(first: 50) {
            nodes {
              body
              author { login }
              createdAt
              url
            }
          }
        }
      }
    }
  }
}' -f owner="<OWNER>" -f repo="<REPO>" -F number=<NUMBER>
```

### 4. Filter for unresolved concerns

From the review threads, keep only those where:

- `isResolved` is `false`
- The thread contains an actionable concern (not just a question with no code implication, not praise, not an acknowledgment)

Discard threads that are:

- Already resolved
- Marked as outdated (`isOutdated: true`) — unless the concern still applies to current code
- Pure informational comments with no requested change
- Comments from the PR author themselves that are self-notes or responses (unless they contain a TODO or action item)

### 5. Validate each concern

For each unresolved thread, read the relevant source file and surrounding context to determine if the concern is valid:

1. **Read the file** at the path indicated by the review thread.
2. **Understand the concern** — what is the reviewer asking to change and why?
3. **Assess validity**:
   - Does the concern point to a real bug, security issue, or code quality problem?
   - Is it a legitimate style/convention issue per the project's standards (see CLAUDE.md)?
   - Is it a reasonable improvement that aligns with the codebase patterns?
   - Or is it based on a misunderstanding of the code?

Categorize each concern as:

| Category | Action |
|----------|--------|
| **Valid fix** | Implement the fix |
| **Valid but out of scope** | Note it but skip — mention in summary |
| **Disagreement** | The reviewer's suggestion would make the code worse or is based on a misunderstanding — explain why in summary |
| **Needs clarification** | The comment is ambiguous — note in summary for user to address |

Once you've categorized everything, give the user a chance to intervene in case they disagree with your assessment.

### 6. Implement fixes

Once the user approves, you can implement any needed fixes.

For each concern categorized as **Valid fix**:

1. Read the full file to understand context before making changes.
2. Implement the fix following the project's code style and conventions.
3. Keep changes minimal and focused — fix exactly what was requested, don't refactor surrounding code.
4. If the fix requires changes to translations, tests, or related files, make those changes too.

### 7. Present summary

After all fixes are applied, present a summary:

```markdown
## PR Comment Resolution Summary

**PR**: #<number> — <title>
**Unresolved threads found**: X
**Fixed**: Y
**Skipped**: Z

### Fixed

- **[file:line]** <brief description of concern> — <what was changed>
- ...

### Skipped

- **[file:line]** <brief description> — **Reason**: <why it was skipped>
- ...

### Needs Clarification

- **[file:line]** <brief description> — <what is unclear>
- ...
```

### 8. Ask about next steps

After presenting the summary, ask the user:

1. **Commit changes** — Stage and commit the fixes
2. **Review individual fixes** — Walk through each change for approval
3. **No further action** — Done

## Important Notes

- Always check out the PR branch before making changes. If you're not already on the correct branch, use `gh pr checkout <URL>` first.
- Never force-push or amend existing commits without explicit user permission.
- If a review comment references code that no longer exists at the indicated line, search for the relevant code in the current version of the file before giving up.
- When multiple comments in the same thread discuss a concern, read the entire thread to understand the full context and any follow-up agreements before implementing a fix.
- Respect the project's CLAUDE.md conventions for code style, translations, CSS, and component patterns.
