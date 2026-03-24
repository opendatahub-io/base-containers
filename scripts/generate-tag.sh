#!/usr/bin/env bash

set -euo pipefail

COMMIT="${1:-HEAD}"
SOURCE_DIR="${2:-.}"
MAJOR=1

COMMIT_DATE=$(TZ=UTC git -C "${SOURCE_DIR}" log -1 --format="%ad" --date=format-local:"%Y%m%d" "${COMMIT}")
# Count first-parent commits on the same day that came before COMMIT.
# --first-parent follows only the main line, so BUILD_NUM reflects merge count, not branch activity.
BUILD_NUM=$(TZ=UTC git -C "${SOURCE_DIR}" log --first-parent "${COMMIT}^" --format="%ad" --date=format-local:"%Y%m%d" \
  | grep -c "^${COMMIT_DATE}$")

echo -n "${MAJOR}.${COMMIT_DATE}.${BUILD_NUM}"