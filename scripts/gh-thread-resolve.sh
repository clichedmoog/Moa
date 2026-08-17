#!/bin/bash
# Resolve a GitHub PR review thread
# Usage: bash scripts/gh-thread-resolve.sh <thread_id>
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <thread_id>" >&2
  exit 1
fi

THREAD_ID="$1"

gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId="$THREAD_ID"
