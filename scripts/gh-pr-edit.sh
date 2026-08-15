#!/bin/bash
# Update a GitHub Pull Request body
# Usage: bash scripts/gh-pr-edit.sh <pr_number> <body>
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <pr_number> <body>" >&2
  exit 1
fi

PR_NUMBER="$1"
BODY="$2"

if [ -z "$BODY" ]; then
  echo "Error: refusing to write an empty PR body" >&2
  exit 1
fi

gh pr edit "$PR_NUMBER" --body "$BODY"
