#!/bin/bash
# Reply to a GitHub PR review thread
# Usage: bash scripts/gh-thread-reply.sh <thread_id> <body>
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <thread_id> <body>" >&2
  exit 1
fi

THREAD_ID="$1"
BODY="$2"

gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}' -f threadId="$THREAD_ID" -f body="$BODY"
