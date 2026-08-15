---
name: merge-pr
description: >-
  Merge an open PR into main after verifying it is actually ready. Use whenever the user says
  "머지하자", "PR 머지해줘", "이 PR 머지해", "merge this PR", or otherwise explicitly asks to merge
  an open PR. Merging never happens without such an explicit request — this skill IS that request.
---

# Merge PR (main)

Merging is a binding, hard-to-reverse action, so this skill verifies readiness first and reports
exactly what it checked — and what it could not check.

```
Step 1  Resolve PR       → OPEN, base main, not draft, MERGEABLE, no unpushed work (else STOP/ask)
Step 2  Verify readiness → CI green (if any), zero unresolved review threads (verified, not assumed)
Step 3  Squash merge     → pinned to the verified head SHA
Step 4  Confirm merged   → only then delete remote branch, fetch origin/main
Step 5  Report
```

## Step 1 — Resolve the PR

```bash
gh pr view <n> --json number,title,state,baseRefName,headRefName,isDraft,mergeable,mergeStateStatus,headRefOid
```

(PR number from the argument, or the current branch's PR when none is given.)

- **State is not OPEN** → report (already merged / closed) and stop.
- **Draft** → it has not been finalized; suggest `/pr auto` first. Only run `gh pr ready` and continue
  if the user explicitly says to merge right now — and say out loud that this path skips the Quality
  Gate `/pr auto` would have run (and, on a public repo, merges before CodeRabbit ever reviews).
- **Base is not `main`** → unusual for this repo; show the base and ask before proceeding.
- **`mergeable` is `CONFLICTING`** (or `mergeStateStatus` `DIRTY`) → STOP; point the user at `/rebase`.
  `UNKNOWN` → GitHub computes mergeability asynchronously; re-poll a few times before deciding.
- **Unpushed local commits**: when the PR branch is the current checkout, `git rev-parse HEAD` must
  equal `headRefOid` — if not, local work exists that the squash would silently exclude → report and stop.

## Step 2 — Verify readiness

A failed check is NOT a passed check — every verification here must distinguish "verified clean"
from "could not verify", and only the former passes the gate.

- **CI**: `gh pr checks <n>`. Treat only the explicit "no checks reported" output as absence of CI
  (normal for now; note it in the report). Failing or still-pending checks → **STOP and report** —
  unlike `/pr auto`, do not poll here; pending means not ready, and `/pr auto` is the tool that
  drives it green. Any other error (auth, network, unknown) → STOP; an unverifiable CI state is
  not a green one.
- **Review threads**: run the paginated `reviewThreads` GraphQL query from
  `.claude/commands/pr.md` § `resolve` step 4, following `pageInfo` to completion. Unresolved
  threads → STOP and point the user at `/pr resolve`. The query erroring or returning an unexpected
  shape → STOP — never conflate "could not fetch threads" with "no unresolved threads".

## Step 3 — Merge

```bash
gh pr merge <n> --squash --match-head-commit <headRefOid>
```

Squash is the repo default — one commit per PR on `main`, titled after the PR. `--match-head-commit`
pins the merge to the SHA Step 2 verified; if it rejects, someone pushed in between — re-run Step 2
against the new tip and report. (`gh pr merge` is deliberately NOT in the permission allowlist — the
prompt is the backstop behind the explicit-request rule; do not "fix" it into the allowlist.)

## Step 4 — Confirm the merge landed, then clean up

- **Gate all cleanup on the merge having actually happened**:
  `gh pr view <n> --json state,mergeCommit` must show `MERGED` with a non-null `mergeCommit`.
  Anything else → STOP and report the merge failure — deleting the branch of an unmerged PR
  destroys real work.
- Delete the remote branch: `git push origin --delete <headRefName>`. A "remote ref does not exist"
  error is benign (GitHub auto-delete got there first) — treat as success; report other errors
  rather than retrying. (This is why the merge doesn't use `--delete-branch`: that flag also
  removes/switches the local checkout, which breaks Orca-managed worktrees.)
- **Leave the local branch alone when a worktree holds it** — worktree cleanup handles it later.
- `git fetch origin main` so subsequent diffs see the merge.

## Step 5 — Report

State: merged PR number/title, squash SHA (from `mergeCommit`), CI status at merge time (green or
absent — could-not-verify never reaches this step), remote branch deletion result, and the local
branch note.

## Guardrails

- **Never merge over failing, pending, or unverifiable CI** — absence of CI is noted, not silently ignored.
- **Never merge with unresolved review threads** — and never treat a failed thread query as zero threads.
- **Never clean up before confirming `MERGED`.**
