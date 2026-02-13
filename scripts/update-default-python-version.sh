#!/bin/bash
# =============================================================================
# ODH Base Containers - Update Default Python Version
# =============================================================================
#
# Updates the default Python version across CI and tooling files:
#   - .github/workflows/ci.yml (python-version defaults)
#   - pyproject.toml (target-version, python_version)
#   - tox.ini (basepython)
#   - renovate.json (description, allowedVersions)
#
# Prerequisite: the python/<new-version>/ directory must already exist.
# Use ./scripts/generate-containerfile.sh python <version> to create it first.
#
# The current default Python version is auto-detected from pyproject.toml.
#
# Usage:
#   ./scripts/update-default-python-version.sh <new-version>            # dry-run (default)
#   ./scripts/update-default-python-version.sh <new-version> --apply    # apply changes
#
# Examples:
#   ./scripts/update-default-python-version.sh 3.13           # preview changes
#   ./scripts/update-default-python-version.sh 3.13 --apply   # apply changes
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Global: set in main(), read by step functions
DRY_RUN="true"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
log_dry()   { echo -e "${CYAN}[DRY-RUN]${NC} $*"; }

PROG_NAME="$(basename "$0")"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Escape BRE pattern-side metacharacters. Safe for version strings (X.Y) only.
sed_escape() {
    printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'
}

# sed -i wrapper that warns (but does NOT fail) when no changes are detected.
checked_sed() {
    local description="$1" file="$2"
    shift 2

    local before after
    before=$(md5sum < "${file}")
    sed -i "$@" "${file}"
    after=$(md5sum < "${file}")

    if [[ "${before}" == "${after}" ]]; then
        log_warn "No changes made for: ${description} in $(basename "${file}")"
    fi
}

detect_current_version() {
    local pyproject="${PROJECT_ROOT}/pyproject.toml"
    if [[ ! -f "${pyproject}" ]]; then
        log_error "pyproject.toml not found"
        exit 1
    fi

    local version
    version=$(grep '^python_version' "${pyproject}" 2>/dev/null \
        | head -1 \
        | sed 's/.*"\([0-9]*\.[0-9]*\)".*/\1/') || true

    if [[ -z "${version}" ]]; then
        log_error "Could not detect current Python version from pyproject.toml"
        exit 1
    fi
    echo "${version}"
}

validate_version() {
    local version="$1"
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: '${version}' (expected X.Y, e.g. 3.13)"
        exit 1
    fi
    if [[ "${version%%.*}" -lt 3 ]]; then
        log_error "Python 2.x is not supported"
        exit 1
    fi
}

require_files() {
    local file
    for file in "$@"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Required file not found: ${file}"
            exit 1
        fi
    done
}

print_usage() {
    cat <<EOF
Usage: ${PROG_NAME} <new-version> [--apply]

Update the default Python version across CI and tooling files.
The current default version is auto-detected from pyproject.toml.
By default, runs in dry-run mode (preview only).

Prerequisites:
  The python/<new-version>/ directory must already exist.
  Use ./scripts/generate-containerfile.sh python <version> to create it.

Arguments:
  <new-version>    Python version to switch to (e.g., 3.13, 3.14)
  --apply          Apply changes (default: dry-run)

Examples:
  ${PROG_NAME} 3.13           # Preview what would change
  ${PROG_NAME} 3.13 --apply   # Apply all changes
EOF
}

# -----------------------------------------------------------------------------
# Update CI and tooling files to the new default version
# -----------------------------------------------------------------------------
update_ci_and_tooling() {
    local old="$1" new="$2"
    local old_nodot="${old//./}" new_nodot="${new//./}"
    local old_esc
    old_esc=$(sed_escape "${old}")

    log_step "Update CI and tooling to Python ${new}"

    local ci_yml="${PROJECT_ROOT}/.github/workflows/ci.yml"
    local pyproject="${PROJECT_ROOT}/pyproject.toml"
    local tox_ini="${PROJECT_ROOT}/tox.ini"
    local renovate="${PROJECT_ROOT}/renovate.json"

    require_files "${ci_yml}" "${pyproject}" "${tox_ini}" "${renovate}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "  .github/workflows/ci.yml: python-version \"${old}\" -> \"${new}\""
        log_dry "  .github/workflows/ci.yml: test matrix auto-expands (discovers python/*/ dirs at runtime)"
        log_dry "  pyproject.toml: target-version, python_version (requires-python stays >= ${old})"
        log_dry "  tox.ini: basepython"
        log_dry "  renovate.json: description and allowedVersions"
        return
    fi

    # CI test matrix auto-expands: it discovers python/*/ directories at runtime
    # via fromJSON(needs.changes.outputs.python-versions), so no sed needed here.

    # Intentionally updates ALL jobs — they should all use the new default Python.
    # Match optional patch suffix (e.g. "3.12.9") since Renovate may pin patch versions.
    checked_sed "CI python-version default" "${ci_yml}" \
        "s/python-version: \"${old_esc}\(\.[0-9]*\)\?\"/python-version: \"${new}\"/g"
    log_info "  Updated .github/workflows/ci.yml"

    # requires-python stays at the old minimum — both versions are supported
    log_info "  Keeping requires-python >= ${old} (both ${old} and ${new} supported)"

    checked_sed "pyproject.toml version update" "${pyproject}" \
        -e "s/target-version = \"py${old_nodot}\"/target-version = \"py${new_nodot}\"/" \
        -e "s/python_version = \"${old_esc}\"/python_version = \"${new}\"/"
    log_info "  Updated pyproject.toml"

    checked_sed "tox.ini basepython update" "${tox_ini}" \
        "s/basepython = python${old_esc}/basepython = python${new}/"
    log_info "  Updated tox.ini"

    checked_sed "renovate.json version update" "${renovate}" \
        -e "s/Pin Python to ${old_esc}\.x/Pin Python to ${new}.x/" \
        -e "s/\"~${old_esc}\"/\"~${new}\"/"
    log_info "  Updated renovate.json"
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
    local new="$1"

    echo ""
    echo "==========================================================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}DRY-RUN COMPLETE${NC} — no files were modified"
        echo ""
        echo "To apply these changes, run:"
        echo "  ${PROG_NAME} ${new} --apply"
    else
        echo -e "${GREEN}DONE${NC}"
        echo ""
        echo "Files modified:"
        echo "  ~ .github/workflows/ci.yml"
        echo "  ~ pyproject.toml"
        echo "  ~ tox.ini"
        echo "  ~ renovate.json"
        echo ""
        echo "Next steps:"
        echo "  1. Build and test: ./scripts/build.sh python-${new}"
        echo "  2. Review changes:  git diff"
    fi
    echo "==========================================================================="
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
        print_usage
        exit 0
    fi

    if [[ $# -lt 1 ]]; then
        log_error "Missing new version argument"
        print_usage
        exit 1
    fi

    local new_version="$1"
    shift

    if [[ $# -gt 0 ]]; then
        case "$1" in
            --apply) DRY_RUN="false" ;;
            *)
                log_error "Unknown option: '$1' (did you mean --apply?)"
                print_usage
                exit 1
                ;;
        esac
        shift
    fi

    if [[ $# -gt 0 ]]; then
        log_error "Unexpected extra arguments: $*"
        print_usage
        exit 1
    fi

    validate_version "${new_version}"

    local old_version
    old_version=$(detect_current_version)

    if [[ "${old_version}" == "${new_version}" ]]; then
        log_error "New version is the same as current version (${old_version})"
        exit 1
    fi
    # sort -V is a GNU coreutils extension
    if [[ "$(printf '%s\n%s' "${old_version}" "${new_version}" | sort -V | tail -1)" != "${new_version}" ]]; then
        log_error "New version (${new_version}) is not newer than current version (${old_version})"
        exit 1
    fi
    if [[ ! -d "${PROJECT_ROOT}/python/${old_version}" ]]; then
        log_error "python/${old_version}/ directory not found"
        exit 1
    fi
    if [[ ! -d "${PROJECT_ROOT}/python/${new_version}" ]]; then
        log_error "python/${new_version}/ directory not found"
        log_error "Run ./scripts/generate-containerfile.sh python ${new_version} first"
        exit 1
    fi

    if [[ "${DRY_RUN}" == "false" ]]; then
        trap 'log_error "Script failed — partial changes may exist. Use \"git checkout -- .\" to revert."' ERR
    fi

    log_info "Current default: Python ${old_version}"
    log_info "Switching to:    Python ${new_version}"
    [[ "${DRY_RUN}" == "true" ]] && log_info "Mode:            dry-run (pass --apply to make changes)"
    echo ""

    update_ci_and_tooling "${old_version}" "${new_version}"

    trap - ERR

    print_summary "${new_version}"
}

main "$@"
