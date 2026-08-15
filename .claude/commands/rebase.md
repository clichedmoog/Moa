---
description: Rebase current branch onto main (or specified base branch) and force push
---

Rebase the current branch onto the latest `$ARGUMENTS` (default: `main`) and force push.

Steps:
1. `git fetch origin <base>`
2. If there are unstaged changes, `git stash` first
3. `git rebase origin/<base>`
4. If rebase succeeds:
   - `git push --force-with-lease`
   - If stashed, `git stash pop`
   - Show success message
5. If rebase has conflicts:
   - Show the conflicting files
   - Ask the user how to proceed (resolve or abort)
   - If stashed, remind user about stash

Usage:
- `/rebase` — rebase onto main
