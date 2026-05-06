#!/usr/bin/env bash

set -euo pipefail

COMMIT="${1:-HEAD}"
SOURCE_DIR="${2:-.}"
MAJOR=1

COMMIT_DATE=$(TZ=UTC git -C "${SOURCE_DIR}" log -1 --format="%ad" --date=format-local:"%Y%m%d" "${COMMIT}")

if git -C "${SOURCE_DIR}" rev-parse --verify "${COMMIT}^" >/dev/null 2>&1; then
  BUILD_NUM=$(TZ=UTC git -C "${SOURCE_DIR}" log --first-parent "${COMMIT}^" --format="%ad" --date=format-local:"%Y%m%d" \
    | grep -c "^${COMMIT_DATE}$" || true)
else
  BUILD_NUM=0
fi

echo -n "${MAJOR}.${COMMIT_DATE}.${BUILD_NUM}"
