---
name: merge-pr
description: >-
  Merge an open PR into main after verifying it is actually ready. Use whenever the user says
  "머지하자", "PR 머지해줘", "이 PR 머지해", "merge this PR", or otherwise explicitly asks to merge
  an open PR. Merging never happens without such an explicit request — this skill IS that request.
---

# Merge PR (main)

Merging is a binding, hard-to-reverse action, so this skill verifies readiness first and reports
exactly what it checked. PRs in this repo are never merged without an explicit user request.

```
Step 1  Resolve PR        → state OPEN, base main, not a draft (else STOP/ask)
Step 2  Verify readiness  → CI green (if any), no unresolved review threads
Step 3  Squash merge      → gh pr merge <n> --squash
Step 4  Clean up + sync   → delete remote branch, fetch origin/main
Step 5  Report
```

## Step 1 — Resolve the PR

```bash
gh pr view <n-or-current> --json number,title,state,baseRefName,headRefName,isDraft
```

- **State is not OPEN** → report (already merged / closed) and stop.
- **PR is a draft** → it has not been finalized; suggest `/pr auto` first. Only `gh pr ready` and
  continue if the user explicitly wants to merge right now.
- **Base is not `main`** → unusual for this repo; show the base and ask before proceeding.

## Step 2 — Verify readiness

- **CI**: `gh pr checks <n>` — no checks configured is normal for now; note it. Failing or still
  pending checks → **STOP and report**; never merge over a red or unfinished CI.
- **Review threads**: fetch review threads via GraphQL (`reviewThreads(first: 100)` with
  `pageInfo` pagination, same query as the `/pr` command's `resolve` action) and check for
  `isResolved == false`. Unresolved threads → STOP and point the user at `/pr resolve`.

## Step 3 — Merge

```bash
gh pr merge <n> --squash
```

Squash is the repo default — one commit per PR on `main`, titled after the PR.

## Step 4 — Clean up and sync

- Delete the remote branch: `git push origin --delete <headRefName>`
- **Leave the local branch alone when it is checked out in a worktree** (Orca-managed worktrees
  hold a checkout; deleting or switching it breaks the worktree). Just note that worktree cleanup
  handles it later.
- `git fetch origin main` so subsequent diffs see the merge.

## Step 5 — Report

State: merged PR number/title, squash SHA (`gh pr view <n> --json mergeCommit`), CI status at merge
time, remote branch deletion result, and local branch note.

## Guardrails

- **Explicit request only** — never merge because work "seems done".
- **Never merge over failing or pending CI**; absence of CI is noted, not silently ignored.
- **Never merge with unresolved review threads** — resolve or get the user's explicit override first.
