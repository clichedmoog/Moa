---
description: "PR workflow — create, resolve, update, auto, review (e.g., /pr create, /pr auto)"
---

Execute PR workflow based on the provided action: $ARGUMENTS

## Project Context (read before any action)

- **Repo**: `clichedmoog/Moa` (private, personal) — macOS SwiftUI app that normalizes NFD Korean filenames to NFC. Base branch is always **`main`**.
- **CodeRabbit is visibility-gated.** The repo is private today and planned to go public later. CodeRabbit's free plan provides line-by-line PR reviews **only on public repos** — on private repos it is PR summarization only (verified 2026-08). At the start of `auto` or `resolve`, check once per run:
  ```bash
  gh api repos/{owner}/{repo} --jq .visibility   # "private" | "public" (gh expands the placeholders from the current repo)
  ```
  - **`private`** → **skip every step marked [CodeRabbit — public only]**: never wait for, poll, or trigger `@coderabbitai`; the global CLAUDE.md rule about CodeRabbit reviewing all PRs does not apply. The local [Pre-PR Quality Gate](#pre-pr-quality-gate) IS the review.
  - **`public`** → run the [CodeRabbit — public only] steps. The free tier is still rate-limited (~4 PR reviews/hour), so the draft-first + batched-push discipline in `auto` is what keeps within it: CodeRabbit skips draft PRs by default, so every WIP push is free, and each push to a *ready* PR costs one auto-review. These rules supersede the global CLAUDE.md CodeRabbit guidance in both modes (the fallback trigger is `@coderabbitai full review`, and review state is read from comment bodies — never from `gh pr checks`).
  - The command failing, or printing anything other than those two values → report the error and ask the user; never guess visibility.
  - The Quality Gate always runs regardless of visibility — when public, it means CodeRabbit's pass lands on already-clean code.
- **Diff base**: run `git fetch origin main` at the start of a run; if local `main` is stale or absent (git worktrees), read every `main...HEAD` in this file as `origin/main...HEAD`.
- **No browser automation.** This workflow never opens a browser, boots servers, or captures screenshots. Verification = build + unit tests + the human walking the 테스트 계획 by running the app.
- **Toolchain may not exist yet** (pre-code repo). Every format/build/test step below is conditional on the tool or config actually existing — when absent, skip with a one-line note instead of failing. Detection:
  - Xcode project (`*.xcodeproj` / `*.xcworkspace`) → `xcodebuild -scheme Moa build` / `xcodebuild -scheme Moa test`
  - SwiftPM only (`Package.swift`) → `swift build` / `swift test`
  - Formatter: run only if a config exists (`.swiftformat`, `.swift-format`, or `.swiftlint.yml`) — SwiftFormat: `swiftformat <files>`; SwiftLint: `swiftlint --fix <files>`

## Available Actions

### create
Open a **draft** PR early — right after the first commit — so WIP is visible and the finalize work (`auto`) stays deferred. The quality gate does NOT run here. When the repo is public, the draft state also keeps CodeRabbit silent (drafts are not auto-reviewed by default), so every WIP push costs zero reviews until `auto` marks the PR ready.

1. **Base branch**: `main`. If the branch name starts with `hotfix`, add `[Hotfix]` prefix to the PR title.
2. **Commit pending work**: `create` is meant to run right after your first commit. If there are uncommitted changes, stage and commit them with proper `type(scope): subject` format (lowercase subject). If nothing is committed vs `main` yet, make that first commit now.
3. **Light format only** (no quality gate, no build):
   - Detect changed files: `git diff --name-only --diff-filter=ACMR main...HEAD`
   - Run the configured formatter on changed `.swift` files only (see Project Context detection). No formatter configured → skip.
   - Amend or add a follow-up commit if formatting changed anything.
4. **Create the PR as a DRAFT** (the helper pushes the current branch itself before calling `gh pr create` — no separate push needed):
   ```bash
   bash scripts/gh-pr-create.sh "<title>" "<body>" main draft
   ```
   - Title: `type(scope): subject` in English (lowercase subject)
   - Body: Korean, using the [PR Body Template](#pr-body-template) below. 변경 사항 / 테스트 계획 may be partial at this stage — `auto` refreshes the body at finalize.
5. **Return the draft PR URL.**

### resolve
Resolve review comments and fix CI failures:

1. **Check repo visibility** (per Project Context — decides the [CodeRabbit — public only] steps), then get the current PR number: `gh pr view --json number`
2. **Detect branch type** from the branch name (see [Review Evaluation Guidelines](#review-evaluation-guidelines))
3. **Check CI**: `gh pr checks <NUMBER>` — this repo may have no CI configured yet; if there are no checks, note it and skip to step 4.
   - All passed → step 4. Still running → note which and continue.
   - Failing → for each failed check: `gh run view <run-id> --log-failed`, classify and fix:
     - **build failure** → read the compiler error, fix the code
     - **test failure** → read failed test output, fix the failing test or the code it tests
     - **lint/format failure** → run the configured formatter/linter on changed files
     - After fixes: re-run the local build/test (see Project Context detection) → commit → push
4. Fetch ALL unresolved review threads (including nitpicks) — when the repo is public this includes `coderabbitai[bot]` threads; evaluate them like any other reviewer's per the guidelines:
   ```bash
   gh api graphql -f query='
   query($cursor: String) {
     repository(owner: "clichedmoog", name: "Moa") {
       pullRequest(number: <NUMBER>) {
         reviewThreads(first: 100, after: $cursor) {
           pageInfo { hasNextPage endCursor }
           nodes { id isResolved comments(first: 20) { nodes { author { login } path body } } }
         }
       }
     }
   }' --jq '.data.repository.pullRequest.reviewThreads'
   ```
   Filter on `isResolved == false`; the `id` (`PRRT_…`) is what the reply/resolve helpers below take — never a REST comment ID. **Follow pagination** (`-F cursor=<endCursor>`) until `hasNextPage` is false before declaring the thread list complete.
5. **Evaluate each suggestion** using the Review Evaluation Guidelines
6. Apply accepted suggestions → format changed files → commit and push. **[CodeRabbit — public only]** Batch all fixes into one push — each push to a ready PR triggers a new auto-review against the rate-limited free tier
7. **Reply and resolve** all review threads (accepted and rejected alike). Use the helper scripts — NEVER `gh pr comment` for thread replies (it breaks conversation threading):
   ```bash
   bash scripts/gh-thread-reply.sh "<thread_id>" "<reply body>"
   bash scripts/gh-thread-resolve.sh "<thread_id>"
   ```
8. Confirm all steps completed

### update
Update the current PR body based on actual code changes.

1. **Get current PR**: `gh pr view --json number,title,body,baseRefName` — no PR for the branch → inform the user and stop
2. **Analyze changes**: `git diff main...HEAD` and `git log main...HEAD --oneline`
3. **Extract manual trailing content** per [Manual Trailing Content Preservation](#manual-trailing-content-preservation), and **capture 테스트 계획 checkbox states** per [Checkbox State Preservation](#checkbox-state-preservation-inside-the-template) — regeneration resets every `- [x]` unless carried over.
4. **Regenerate the body**: keep the template format (변경 사항, 테스트 계획), update both sections from the actual diff (follow [Test Plan Guidelines](#test-plan-guidelines)), keep the hidden `<!-- pr-body-end -->` marker, re-append trailing content verbatim.
5. **Show diff**: old vs new body for user review before applying; mention whether trailing content was preserved.
6. **Apply**: `bash scripts/gh-pr-edit.sh <NUMBER> "<body>"`
7. **Confirm**: show the PR URL

### auto
**Finalize** a draft PR: ensure draft → quality gate → build & test gate → mark ready → resolve loop → body update → report. Run this when the work is complete.

Also works **standalone**: if no PR exists yet for the branch, `auto` runs the `create` steps first, then finalizes — `/pr auto` alone takes committed work to a clean, reviewed PR in one shot.

1. **Check repo visibility** (per Project Context — decides the [CodeRabbit — public only] steps), then **ensure a PR exists**: `gh pr view --json number,isDraft` — no PR → run the `create` action first.
2. **Quality gate**: run the [Pre-PR Quality Gate](#pre-pr-quality-gate) (agent fleet). Apply `Critical`/`Important` fixes.
3. **Build & test gate**: run format on changed files, then build and test per the Project Context detection. **Block on build/test failure** — fix and re-run until clean. No project/toolchain yet → skip with a note. Commit and push.
4. **Mark ready**: if still a draft, `gh pr ready <NUMBER>`.
   - **[CodeRabbit — public only]** The draft→ready transition fires CodeRabbit's auto-review (drafts are skipped by default, so all WIP pushes were free — this is the first review). After marking ready, **poll for the review with a timeout**: every 30s (max ~5 min) read the latest `coderabbitai[bot]` comment — do NOT trust `gh pr checks`, which reports `pass` even when the review was skipped by a rate limit:
     ```bash
     gh api "repos/{owner}/{repo}/issues/<NUMBER>/comments?sort=updated&direction=desc&per_page=100" \
       --jq 'map(select(.user.login=="coderabbitai[bot]")) | .[0] | {updated:.updated_at, body:.body}'
     ```
     (`sort=updated&direction=desc` matters — the default REST order is oldest-first, so an unsorted first page misses the newest comment once a PR has more than one page of them.)
     - **Reviewed** ⇒ a Walkthrough/Summary comment whose commit range ends at the latest pushed SHA (or actionable threads posted against it) → proceed to the loop.
     - **Rate-limited** ⇒ body contains `Review limit reached` — wait until the stated reset time (+30s), then post **one** `@coderabbitai full review` (budget: max **1** manual trigger per PR; use `full review`, not plain `review`, which no-ops on already-seen commits). Still nothing after another ~3 min → stop waiting, note it in the report; the Quality Gate already reviewed locally.
     - No `coderabbitai[bot]` comment ever appears (~5 min) ⇒ before concluding anything, also check `gh api repos/{owner}/{repo}/pulls/<NUMBER>/reviews --paginate` for a `coderabbitai[bot]` review — a review delivered only as inline threads is invisible to the issue-comment poll. Nothing there either ⇒ CodeRabbit is likely not installed on this repo — note it in the report and continue without it.
5. **Resolve loop** (until the branch is stable):
   a. `gh pr checks <NUMBER>` — no checks configured → skip. Still running → `sleep 30` and re-check (max 10 re-checks); re-checks exhausted with checks still pending → **stop the loop and report which checks are pending** — never treat pending as passing. Failing → fix per the `resolve` action's CI-failure step.
   b. Resolve any unresolved review threads per the `resolve` action (paginated fetch → evaluate → apply → reply/resolve).
   c. **[CodeRabbit — public only]** Batch ALL fixes from 5a+5b into a **single push per iteration** — every push to a ready PR costs one auto-review, so per-fix pushes multiply reviews and burn the ~4/hour free-tier limit. Never manually trigger `@coderabbitai` inside the loop; the batched push re-reviews on its own.
   d. **Exit condition**: CI green (or absent) + all threads resolved + no unpushed work → exit loop.
   e. Loop guards: same check failing 2 consecutive iterations with the same error → stop and report. 10 iterations → warn; 20 → abort and report.
6. **Update PR body**: compare body against `git diff main...HEAD`; if outdated, regenerate per the `update` action (trailing content + checkbox preservation rules apply).
7. **Report final status**: checks passed, threads resolved, iterations, which quality-gate slots ran degraded (if any), and the CodeRabbit outcome — reviewed / rate-limited / not installed / skipped (private repo).

### review
Review **someone else's PR** (`/pr review 12`). Read-and-comment path — never push to their branch.

1. **Read every comment source** — inline threads alone miss things:
   - `gh api repos/{owner}/{repo}/pulls/<n>/reviews --paginate` (review bodies)
   - `gh api repos/{owner}/{repo}/pulls/<n>/comments --paginate` (inline)
   - `gh api repos/{owner}/{repo}/issues/<n>/comments --paginate` (issue-level — includes `coderabbitai[bot]` when the repo is public; whatever CodeRabbit already flagged, do not repeat in your own comment)

   `--paginate` is not optional — the default page is 30 items and a well-reviewed PR exceeds that in inline comments alone.
2. **Read the diff (`gh pr diff <n>`) and trace each concern to a real code path.** Follow the path to its end before writing anything down — a theoretical risk that cannot actually occur must not be posted. If the diff touches rename/traversal logic, load the domain pitfalls from `HANDOFF.md` §5 (see [Domain context injection](#domain-context-injection)).
3. **테스트 계획**: this workflow does not run the app for someone else's PR (no automated verification). Verify what you can by code reading and record a per-item verdict; report which items still need the author's manual run. Do NOT touch their PR body yet — ticking happens in step 5, after sign-off.
4. **Draft the comment and show it to the user first.** Never post or approve before that review. Tone: author is Claude — say so; dry and short, ~요체; no praise, no 총평; nothing left to say → `LGTM 👍` alone; drop low-importance nits entirely.
5. **Post, approve, then tick** — after the user signs off. Post with `gh pr comment <n> --body "<draft>"` (top-level comment, not a thread reply); approve with `gh pr review <n> --approve`. Approve only if nothing you posted is an outstanding Critical finding. Never `REQUEST_CHANGES` unless the user asks. Then tick the boxes you verified: fetch the body **immediately before** the edit (`gh pr view <n> --json body --jq .body` — a stale copy silently clobbers the author's concurrent edits), flip only `- [ ]` → `- [x]` on that fresh copy with every other byte untouched, and write it with `bash scripts/gh-pr-edit.sh <n> "<body>"`.

## Pre-PR Quality Gate

A thorough local review from a fleet of specialized reviewers before the PR goes ready. While the repo is private, **this gate is the only code review a PR gets** — do not skip or thin it out. Once public, it still runs in full: it catches issues before CodeRabbit spends a rate-limited review on them, and it carries the domain context CodeRabbit doesn't have.

### Review scope (applies to EVERY agent below)

Pass each agent an explicit scope — the default unstaged-only diff misses committed branch work:

> Review the **full branch diff against `main` plus any uncommitted working-tree changes**: `git diff main...HEAD` and `git diff HEAD`. Do not limit the review to unstaged changes.

### Domain context injection

Before reviewing, each agent must read **`HANDOFF.md` §5 (기술 배경)** whenever the diff touches filename conversion, filesystem traversal, or rename logic. It records the project's real failure modes:

- Bottom-up (deepest-first) traversal — renaming a parent first invalidates collected child paths
- APFS is normalization-insensitive on comparison: an NFD→NFC rename may need a 2-step rename via a temp name
- HFS+ forces NFD back — conversion is meaningless there; detect and inform
- Skip already-NFC items; don't follow symlinks; don't descend into bundle packages (`.app`, `.rtfd`)
- Name-collision policy must be explicit, never silent

`HANDOFF.md` §5 is the authoritative source — the bullets above are a summary and may lag it (the APFS 2-step-rename question is still marked 실측 필요 there). A reviewer that has not read the file will miss the bugs that actually matter in this codebase.

### Agent availability preflight (BEFORE launching the fleet)

Naming an agent type that is not loaded fails the `Agent` call outright. Check the available agent types first and map each slot:

| Fleet slot | Preferred | Fallback |
|------------|-----------|----------|
| code-review | `pr-review-toolkit:code-reviewer` | `feature-dev:code-reviewer`, then `general-purpose` |
| silent-failure-hunter | `pr-review-toolkit:silent-failure-hunter` | `general-purpose` |
| code-simplifier | `pr-review-toolkit:code-simplifier` | `code-simplifier:code-simplifier`, then `general-purpose` |
| type-design-analyzer | `pr-review-toolkit:type-design-analyzer` | `general-purpose` |
| pr-test-analyzer | `pr-review-toolkit:pr-test-analyzer` | `general-purpose` |
| comment-analyzer | `pr-review-toolkit:comment-analyzer` | `general-purpose` |

When falling back to `general-purpose`, write the slot's focus, the review scope, and the domain context into the prompt yourself — and **report in the final status which slots ran degraded**. One-line fix for next time:

```bash
claude plugin install pr-review-toolkit@claude-plugins-official --scope user
```

### Agent fleet (launch in parallel via `Agent` tool)

**Always run:**
- **code-review**: bugs, logic errors, convention adherence. **Override the confidence filter**: report issues with confidence ≥ 70 and classify each as `Critical` (90-100), `Important` (70-89), or `Nitpick` (50-69).
- **silent-failure-hunter**: swallowed errors, inadequate error handling. High value here — this app **renames the user's files**; a silently failed or half-completed rename pass is data-integrity damage, and every `try?`/ignored-result on a FileManager call is suspect.
- **code-simplifier**: clarity and maintainability while preserving functionality.

**Conditionally run (only when the diff matches):**
- **type-design-analyzer** — when the diff adds or changes Swift types (structs, enums, protocols). Reviews encapsulation and invariant expression.
- **pr-test-analyzer** — when the diff touches the conversion/traversal core logic (per HANDOFF, the core must have unit tests with NFD-filename fixtures generated in code) or modifies test files.
- **comment-analyzer** — when the diff adds or modifies non-trivial comments or docstrings.

**Write "only report — do not modify any file" into every agent prompt** — the simplifier agents edit files by default, mid-fleet and concurrently with the other reviewers. Wait for all agents. An agent that errors out or returns no usable report is a **degraded slot**: retry it once; if it fails again, run its focus yourself or report it exactly like a fallback slot — never count a failed agent as a clean pass. **Apply fixes in order**: code-review → silent-failure-hunter → type-design-analyzer → pr-test-analyzer → code-simplifier → comment-analyzer. Apply `Critical` and `Important` automatically; list `Nitpick`s for the user and apply only those that objectively improve the code. Then format and commit.

## Review Evaluation Guidelines

Detect the branch type from the branch name before evaluating review suggestions.

### Hotfix branches (`hotfix/*`)
Minimal, emergency fixes — **strict scope**:
- Out-of-scope suggestions: reject with reason ("Out of scope for hotfix, will address in a follow-up PR")
- Nitpicks: reject — merge quickly with minimal changes
- Bugs/security/type-safety: always accept

### Regular branches (`feat/*`, `fix/*`, `refactor/*`, `ci/*`, `docs/*`, etc.)
Room for broader improvements — **inclusive quality**:
- Out-of-scope suggestions: accept if they genuinely improve quality/readability/maintainability; reject only large refactors that deserve their own PR or factually wrong suggestions
- Nitpicks: accept if the code gets objectively better; reject pure taste differences
- Bugs/security/type-safety/performance: always accept

### Always accept (all branches)
Actual bugs or runtime error risks · type-safety improvements · security fixes · clear performance wins

### Always reject (all branches)
Factually incorrect or bug-introducing suggestions · suggestions inconsistent with established codebase patterns · over-engineering without clear benefit

## PR Body Template

```markdown
## 변경 사항
- [변경 내용을 bullet point로 작성]

## 테스트 계획
> 이 PR의 변경사항으로 확인이 필요한 동작 목록입니다.

- [ ] [기능/화면] - [확인할 동작]
- [ ] [기능/화면] - [확인할 동작]

<!-- pr-body-end -->
```

### Manual Trailing Content Preservation

Users add extra context **after** the hidden `<!-- pr-body-end -->` marker — screenshots, follow-up notes, links. Any body regeneration (`update`, `auto` step 6) MUST keep that trailing content intact.

**Fetch immediately before writing, not once at the start.** `scripts/gh-pr-edit.sh` replaces the **entire** body, and an `auto` run can spend minutes between reading and writing — anything the user edits in that window is silently destroyed by a write built from a stale copy. Re-fetch right before the write; if the body changed, re-extract trailing content and checkbox states from the **fresh** copy.

**Procedure** (before every `bash scripts/gh-pr-edit.sh` call with a regenerated body):

1. Fetch at write time: `gh pr view <NUMBER> --json body --jq .body`
2. Split on the **first** `<!-- pr-body-end -->` line: `head` (through the marker) / `trailing` (everything after, may be empty)
3. Regenerate `head` from the template
4. Final body = regenerated template + `trailing` **verbatim** (no trimming — treat it as opaque; re-parsing risks corrupting screenshots or attachment URLs)
5. **No marker in the existing body** (hand-written PR) → do not assume anything; skip the auto-update and ask the user how to proceed

### Checkbox State Preservation (inside the template)

The 테스트 계획 checkboxes live **inside** the regenerated template — naive regeneration silently resets every `- [x]` the user ticked. That is real lost work.

**Rule**: never emit a checklist line as `- [ ]` when the current remote body has it as `- [x]`. Only ever flip unchecked → checked, never the reverse.

**Procedure** (same write-time fetched body as above):

1. From the `head` half, within `## 테스트 계획` only, collect checklist lines in document order: checked state + full label text. (Scope matters — trailing content may contain its own checkboxes; don't pull those in.)
2. Generate the new body (all lines default unchecked), then re-apply: **exact full-label match** → carry the checked state. Match duplicates by (label, occurrence index).
3. New labels stay unchecked; ticked labels that no longer exist are dropped with their line — don't re-home them.
4. A reworded item is a different item — carrying a tick onto reworded text asserts a verification that never happened.

If a ticked item's underlying code changed after it was ticked: keep it checked (it is the user's record) and **say so in your reply** so the user can decide whether to re-verify.

**Recovering an already-wiped tick** — GitHub keeps PR body edit history (newest first; page with `-F cursor=<endCursor>` until `hasNextPage` is false):

```bash
gh api graphql -f query='
query($cursor: String) {
  repository(owner: "clichedmoog", name: "Moa") {
    pullRequest(number: <NUMBER>) {
      userContentEdits(first: 50, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { editedAt editor { login } diff }
      }
    }
  }
}'
```

### Test Plan Guidelines

Generate the test plan from the **actual branch diff** (`git diff main...HEAD`):

1. Analyze changed files to identify affected features and behaviors
2. List user-verifiable behaviors — the human runs the app; each item must be checkable by hand
3. Write specific actions, including edge cases when the change involves conditional logic (name collisions, already-NFC files, HFS+ volumes, empty folders)
4. Internal refactors with no behavior change → say so in one line instead of inventing checks

Example for a conversion-core PR:
```markdown
## 테스트 계획
> 이 PR의 변경사항으로 확인이 필요한 동작 목록입니다.

- [ ] NFD 파일명 픽스처 폴더를 드래그앤드롭 - 전체가 NFC로 변환되는지 확인
- [ ] 이미 NFC인 파일 포함 폴더 - 해당 파일은 건너뛰고 수정 시각이 유지되는지 확인
- [ ] 중첩 폴더 (NFD 이름의 폴더 안에 NFD 파일) - 자식부터 변환되어 경로가 깨지지 않는지 확인
- [ ] 이름 충돌 케이스 - 정책대로 동작하는지 확인 (건너뛰기/번호/묻기)
```

## Required Permissions

Pre-approved in `.claude/settings.json` so the workflow runs without manual approval. Prefer these exact commands — alternatives trigger permission prompts.

- **Git**: `git add`, `git commit`, `git push`, `git log`, `git diff`, `git status`, `git branch`, `git fetch`
- **GitHub CLI**: `gh pr view/checks/comment/diff/ready`, `gh api`, `gh run view`, and the four `scripts/gh-*.sh` helpers
- **Format/Build/Test**: `swiftformat`, `swiftlint`, `swift build`, `swift test`, `xcodebuild`
- **Wait**: `sleep` (resolve-loop polling)

**NOT pre-approved — expect a prompt:**

- Raw `gh pr create` / `gh pr edit` — deliberately left out of the allowlist so that creating and editing PRs goes through the wrapper scripts (which ARE allowlisted); an accidental raw call prompts instead of bypassing the body-preservation rules.
- `gh pr review` — used by the `review` action to approve. Deliberately left out: approval is a binding state change on someone else's PR and the prompt is the backstop behind the draft sign-off. ⚠️ The allowlisted `gh api` could technically reach the same mutation — **never use `gh api` to approve, request changes, or merge a PR**; those actions go through their dedicated `gh pr` commands precisely so they prompt.

## Usage Examples

Recommended flow:
- `/pr create` — right after your first commit, open a **draft** PR (quality gate deferred)
- …keep working and committing…
- `/pr auto` — finalize: quality gate → build & test → `gh pr ready` → resolve loop → done

Individual actions:
- `/pr create` - Open a draft PR early (no quality gate)
- `/pr update` - Update PR body based on current code changes
- `/pr resolve` - Resolve review comments and fix CI failures
- `/pr auto` - Finalize a draft PR (or, standalone, take committed work all the way to a reviewed PR)
- `/pr review <n>` - Review someone else's PR: all three comment sources → diff → draft for user sign-off → post/approve
