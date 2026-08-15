#!/bin/bash
# Create a GitHub Pull Request (pushes the current branch first)
# Usage: bash scripts/gh-pr-create.sh <title> <body> [base_branch] [draft]
#   draft: pass "draft" (or "--draft") as the 4th argument to open a draft PR
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <title> <body> [base_branch] [draft]" >&2
  exit 1
fi

TITLE="$1"
BODY="$2"
BASE="${3:-main}"

if [ "$BASE" = "draft" ] || [ "$BASE" = "--draft" ]; then
  echo "Error: 3rd argument is the base branch, got '$BASE' — did you mean: $0 <title> <body> main draft" >&2
  exit 1
fi

DRAFT_FLAG=""
case "${4:-}" in
  draft|--draft) DRAFT_FLAG="--draft" ;;
  "") ;;
  *)
    echo "Error: 4th argument must be 'draft' or omitted, got '${4}'" >&2
    exit 1
    ;;
esac

# gh pr create cannot prompt to push in a non-TTY session, so push explicitly first
git push -u origin HEAD

# shellcheck disable=SC2086  # intentionally unquoted: the empty-array alternative is an unbound-variable error under macOS bash 3.2 + set -u
gh pr create --title "$TITLE" --body "$BODY" --base "$BASE" $DRAFT_FLAG
