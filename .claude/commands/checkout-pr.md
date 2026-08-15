---
description: Read a PR and checkout its branch for local work (e.g., /checkout-pr 3)
---

Checkout the branch for PR #$ARGUMENTS and display a summary.

Steps:
1. Fetch PR details using `gh pr view $ARGUMENTS --json title,body,headRefName,baseRefName,state,changedFiles`
   - On any `gh` error (not found, auth, network), report it and stop
2. **Worktree guard — run BEFORE touching any state**: probe `git worktree list --porcelain` for the PR's head branch. If another worktree already holds it, stop and report that worktree's path (suggest working there instead) — attempting checkout would fail with "already used by worktree", and it must fail before any stash is created.
3. Check for local uncommitted changes with `git status --porcelain`
   - If non-empty: `git stash push -u -m "checkout-pr #$ARGUMENTS"` (`-u` matters — plain `git stash` skips untracked files), then confirm a stash entry was actually created (`git rev-parse -q --verify refs/stash`) before telling the user their changes are stashed
4. `gh pr checkout $ARGUMENTS` — this handles fork PRs, fast-forwards an existing stale local branch, and resolves the remote; do not hand-roll fetch+checkout
   - **If this fails after a stash was created**: `git stash pop` to restore the user's changes, then report the failure and the restored state. If the pop itself conflicts, report the stash ref explicitly — never end the command without stating where the stashed changes are
5. Display a summary:
   - PR title and number
   - Branch name (head → base)
   - State (OPEN, CLOSED, MERGED)
   - Brief description from the PR body — the `## 변경 사항` section when the body follows the `/pr` template; for a hand-written body, the first paragraph
   - Changed files count (`changedFiles`)
   - If changes were stashed: the stash stays un-popped **by design** (popping here would drop the changes onto the PR branch). Print the exact restore command: `git checkout <original-branch> && git stash pop`

Usage:
- `/checkout-pr 3` — checkout PR #3's branch for local work (for the read-only review path use `/pr review 3` instead)
