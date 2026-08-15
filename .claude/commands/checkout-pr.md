---
description: Read a PR and checkout its branch for local work (e.g., /checkout-pr 3)
---

Checkout the branch for PR #$ARGUMENTS and display a summary.

Steps:
1. Fetch PR details using `gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,state,files`
2. If the PR is not found, show an error message and stop
3. Extract the head branch name from the PR data
4. Check for local uncommitted changes using `git status --porcelain`
   - If there are changes, `git stash` them first and inform the user
5. `git fetch origin <branch>` and `git checkout <branch>`
6. Display a summary:
   - PR title and number
   - Branch name (head → base)
   - State (OPEN, CLOSED, MERGED)
   - Brief description from PR body (first section only)
   - Changed files count
   - If changes were stashed, remind the user with `git stash list`

Usage:
- `/checkout-pr 3` — checkout PR #3's branch
- `/checkout-pr 12` — checkout PR #12's branch
