#!/bin/bash

# Lints Containerfiles using Hadolint (https://github.com/hadolint/hadolint)
# Usage:
#   ./scripts/lint-containerfile.sh                    # Lint all Containerfile.* files
#   ./scripts/lint-containerfile.sh Containerfile.python
#   ./scripts/lint-containerfile.sh path/to/Dockerfile
#   ./scripts/lint-containerfile.sh file1 file2 ...   # Lint multiple files
#
# Configuration: .hadolint.yaml in project root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_header() { echo -e "${BLUE}==>${NC} $1"; }

# Hadolint version for container fallback
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.14.0}"

# Global variable for hadolint command (set by check_hadolint)
HADOLINT_CMD=()

# Determine SELinux relabel option for volume mounts, if supported/enforced.
selinux_mount_label() {
    if command -v getenforce &> /dev/null; then
        [[ "$(getenforce 2>/dev/null)" != "Disabled" ]] && echo "Z" && return
        return
    fi

    if [[ -e /sys/fs/selinux/enforce ]]; then
        [[ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" == "1" ]] && echo "Z"
    fi
}

# Check if hadolint is available, fall back to container if not
check_hadolint() {
    local selinux_label=""
    selinux_label="$(selinux_mount_label)"
    local mount_label=""
    if [[ -n "${selinux_label}" ]]; then
        mount_label=",${selinux_label}"
    fi

    if command -v hadolint &> /dev/null; then
        HADOLINT_CMD=(hadolint)
        return 0
    elif command -v podman &> /dev/null; then
        HADOLINT_CMD=(
            podman run --rm -i
            -v "${PROJECT_ROOT}:${PROJECT_ROOT}:ro${mount_label}"
            -w "${PROJECT_ROOT}"
            "ghcr.io/hadolint/hadolint:${HADOLINT_VERSION}"
            hadolint
        )
        return 0
    else
        log_error "hadolint not found. Install it or ensure podman/docker is available."
        return 1
    fi
}

# Lint a single Containerfile/Dockerfile
lint_file() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        log_error "File not found: ${file}"
        return 1
    fi

    log_header "Linting ${file}"

    # Find config file (check current dir, then project root)
    local -a config_arg=()
    if [[ -f ".hadolint.yaml" ]]; then
        config_arg=(--config ".hadolint.yaml")
    elif [[ -f "${PROJECT_ROOT}/.hadolint.yaml" ]]; then
        config_arg=(--config "${PROJECT_ROOT}/.hadolint.yaml")
    fi

    local output exit_code=0
    output=$("${HADOLINT_CMD[@]}" "${config_arg[@]}" "${file}" 2>&1) || exit_code=$?

    # Show output
    [[ -n "${output}" ]] && echo "${output}"

    # Check hadolint exit code
    if [[ ${exit_code} -eq 0 ]]; then
        log_info "✓ ${file} passed linting"
        return 0
    else
        log_error "✗ ${file} has linting errors"
        return 1
    fi
}

# Find all Containerfiles/Dockerfiles in the project
find_containerfiles() {
    # Search in version directories (cuda/12.8/Containerfile, python/3.12/Containerfile)
    # and templates at root level (Containerfile.*.template)
    find "${PROJECT_ROOT}" -maxdepth 3 \( -name "Containerfile*" -o -name "Dockerfile*" \) -type f 2>/dev/null | sort
}

print_usage() {
    echo "Usage: $0 [file...]"
    echo ""
    echo "Lint Containerfiles/Dockerfiles using Hadolint"
    echo ""
    echo "Arguments:"
    echo "  file...   One or more Containerfile/Dockerfile paths to lint"
    echo "            If no files specified, lints all Containerfile.*/Dockerfile.* in project root"
    echo ""
    echo "Examples:"
    echo "  $0                              # Lint all Containerfiles"
    echo "  $0 Containerfile.python         # Lint specific file"
    echo "  $0 Containerfile.*              # Lint matching files"
    echo "  $0 path/to/Dockerfile           # Lint Dockerfile"
    echo ""
    echo "Environment Variables:"
    echo "  HADOLINT_VERSION  - Hadolint container version (default: v2.14.0)"
    echo ""
    echo "Configuration: .hadolint.yaml"
}

main() {
    local exit_code=0
    local files=()

    # Parse arguments
    if [[ $# -eq 0 ]]; then
        # No args: find all Containerfiles
        while IFS= read -r file; do
            files+=("${file}")
        done < <(find_containerfiles)
    else
        for arg in "$@"; do
            case "${arg}" in
                -h|--help|help)
                    print_usage
                    exit 0
                    ;;
                *)
                    files+=("${arg}")
                    ;;
            esac
        done
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No Containerfiles found to lint"
        print_usage
        exit 1
    fi

    log_info "=== Containerfile Linter ==="

    # Check for hadolint before starting
    if ! check_hadolint; then
        exit 1
    fi

    # Lint each file
    for file in "${files[@]}"; do
        lint_file "${file}" || exit_code=1
    done

    echo ""
    if [[ ${exit_code} -eq 0 ]]; then
        log_info "All linting checks passed!"
    else
        log_error "Linting failed. Please fix the errors above."
    fi

    exit ${exit_code}
}

main "$@"
