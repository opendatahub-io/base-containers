#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <IMAGE_URL>" >&2
  exit 1
fi

IMAGE_URL="$1"
REPO_URL="${IMAGE_URL%%:*}"
TODAY=$(date -u +%Y%m%d)
MAJOR=1

TAGS_JSON=$(skopeo list-tags "docker://${REPO_URL}" 2>/dev/null || echo '{"Tags":[]}')

# Extract tags of the form "1.YYYYMMDD.N" that match today's date.
MATCHING=$(grep -oE "1\.${TODAY}\.[0-9]+" <<< "${TAGS_JSON}" || true)

NEXT_BUILD=0
if [[ -n "${MATCHING}" ]]; then
  MAX_BUILD=$(grep -oE '[0-9]+$' <<< "${MATCHING}" | sort -n | tail -1)
  NEXT_BUILD=$((MAX_BUILD + 1))
fi

echo -n "${MAJOR}.${TODAY}.${NEXT_BUILD}"
