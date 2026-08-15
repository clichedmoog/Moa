---
description: Rebase current branch onto main (or specified base branch) and force push
---

Rebase the current branch onto the latest base and force push. Resolve `<base>` = `$ARGUMENTS` if non-empty, else `main`.

Steps:
1. **Guards** — stop with a message if any fail:
   - Current branch (`git branch --show-current`) equals `<base>` or `main` → never rebase/force-push the base branch itself
   - No upstream configured (`git rev-parse --abbrev-ref --symbolic-full-name @{u}` fails) → the branch was never pushed; report there is nothing to force-push and ask whether to rebase locally only
2. `git fetch origin <base>` — fetch ONLY the base. Do not refresh the current branch's remote-tracking ref here; `--force-with-lease` protects against unseen remote commits precisely by comparing against the *last-seen* ref.
3. If there are ANY uncommitted changes — staged, unstaged, or untracked (`git status --porcelain` non-empty) — `git stash push -u -m "rebase: auto-stash"` first. `git rebase` refuses to start on a dirty tree, staged changes included, and plain `git stash` would skip untracked files.
4. `git rebase origin/<base>`
5. If the rebase fails for any reason (conflicts, refused to start, …):
   - Show the conflicting files
   - Ask the user how to proceed (resolve, or `git rebase --abort`)
   - If stashed, state where the stash is — never end without saying so
6. If the rebase succeeds, restore the stash BEFORE pushing (a pop conflict is then handled while the branch is still unpublished):
   - If stashed: `git stash pop`. **On pop conflict**: stop — report that the rebase succeeded but is NOT pushed yet, show the conflicted files, note the stash entry is preserved, and ask how to proceed. Never show a success message over a conflicted tree.
7. `git push --force-with-lease`
   - **On lease rejection**: the remote branch has commits you haven't seen. STOP — fetch the branch, show the user the remote-only commits, and ask how to proceed. NEVER escalate to plain `--force`.
   - **[CodeRabbit — public only]** A force push to a ready (non-draft) PR triggers an auto-review and outdates existing inline review threads. When the repo is public and the branch has a ready PR, say so before pushing.
8. Show the result: rebased onto `<base>`, pushed (or not, and why), and the stash outcome if one existed.

Usage:
- `/rebase` — rebase onto main
- `/rebase feat/some-base` — rebase onto a different base branch
