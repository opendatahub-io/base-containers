#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="${1:-.}"
MAJOR=1

COMMIT_DATE=$(TZ=UTC git -C "${SOURCE_DIR}" log -1 --format="%ad" --date=format-local:"%Y%m%d" HEAD)
# Count commits on the same day that are ancestors of HEAD (i.e., came before it).
# This gives a deterministic, sequential build number from git history — no registry access needed.
BUILD_NUM=$(TZ=UTC git -C "${SOURCE_DIR}" log HEAD^ --format="%ad" --date=format-local:"%Y%m%d" \
  | grep -c "^${COMMIT_DATE}$")

echo -n "${MAJOR}.${COMMIT_DATE}.${BUILD_NUM}"