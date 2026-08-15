#!/bin/bash
# Create a GitHub Pull Request
# Usage: bash scripts/gh-pr-create.sh <title> <body> [base_branch] [draft]
#   draft: pass the literal word "draft" as the 4th argument to open a draft PR
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <title> <body> [base_branch] [draft]" >&2
  exit 1
fi

TITLE="$1"
BODY="$2"
BASE="${3:-main}"

DRAFT_FLAG=""
if [ "${4:-}" = "draft" ]; then
  DRAFT_FLAG="--draft"
fi

gh pr create --title "$TITLE" --body "$BODY" --base "$BASE" $DRAFT_FLAG
