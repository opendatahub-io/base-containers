#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <IMAGE_URL> [SOURCE_DIR]" >&2
  exit 1
fi

IMAGE_URL="$1"
SOURCE_DIR="${2:-$(pwd)}"
MAJOR=1

COMMIT_DATE=$(git -C "${SOURCE_DIR}" log -1 --format="%ad" --date=format:"%Y%m%d" HEAD)
# Count commits on the same day that are ancestors of HEAD (i.e., came before it).
# This gives a deterministic, sequential build number from git history — no registry access needed.
BUILD_NUM=$(git -C "${SOURCE_DIR}" log HEAD^ --format="%ad" --date=format:"%Y%m%d" 2>/dev/null \
  | grep -c "^${COMMIT_DATE}$" || true)

echo -n "${MAJOR}.${COMMIT_DATE}.${BUILD_NUM}"
