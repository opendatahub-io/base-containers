#!/bin/bash
# =============================================================================
# Generate Containerfile and app.conf from Template
# =============================================================================
#
# Generates a version-specific Containerfile from the template and creates
# a starter app.conf by copying from the latest existing version.
#
# Usage:
#   ./scripts/generate-containerfile.sh cuda <version>
#   ./scripts/generate-containerfile.sh python <version>
#
# Examples:
#   ./scripts/generate-containerfile.sh cuda 12.9
#   ./scripts/generate-containerfile.sh cuda 13.0
#   ./scripts/generate-containerfile.sh python 3.13
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Validate version format (X.Y where X and Y are numbers)
validate_version() {
    local version="$1"
    local type="$2"

    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: '${version}'"
        log_error "Expected format: X.Y (e.g., 12.8, 13.0, 3.12)"
        exit 1
    fi

    # Additional validation for known types
    case "${type}" in
        cuda)
            local major="${version%%.*}"
            if [[ "${major}" -lt 12 ]]; then
                log_warn "CUDA version ${version} is older than 12.x - are you sure?"
            fi
            ;;
        python)
            local major="${version%%.*}"
            if [[ "${major}" -lt 3 ]]; then
                log_error "Python 2.x is not supported. Use Python 3.x"
                exit 1
            fi
            ;;
    esac
}

# Check if version directory already exists
check_existing_version() {
    local output_dir="$1"
    local version="$2"
    local type="$3"

    if [[ -d "${output_dir}" ]]; then
        if [[ -f "${output_dir}/Containerfile" ]]; then
            log_error "Directory ${type}/${version}/ already exists with a Containerfile"
            log_error "Remove ${type}/${version}/ first if you want to regenerate it"
            exit 1
        fi
    fi
}

# Escape BRE pattern-side metacharacters. Safe for version strings (X.Y) only.
sed_escape() {
    printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'
}

# Find the latest existing version directory for a given type (e.g., cuda, python)
# Usage: find_latest_version <type> [exclude_version]
find_latest_version() {
    local type="$1"
    local exclude="${2:-}"
    local type_dir="${PROJECT_ROOT}/${type}"

    if [[ ! -d "${type_dir}" ]]; then
        return 1
    fi

    local latest
    if [[ -n "${exclude}" ]]; then
        latest=$(find "${type_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
            | grep -v "^${exclude}$" | sort -V | tail -1) || true
    else
        latest=$(find "${type_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
            | sort -V | tail -1) || true
    fi

    if [[ -z "${latest}" ]]; then
        return 1
    fi

    echo "${latest}"
}

# Create a starter app.conf for a new Python version
create_python_appconf() {
    local new_version="$1"
    local output_dir="$2"
    local new_conf="${output_dir}/app.conf"

    local latest
    latest=$(find_latest_version "python" "${new_version}") || {
        log_warn "No existing python version found; skipping app.conf generation"
        log_warn "Create ${output_dir}/app.conf manually"
        return
    }

    local old_conf="${PROJECT_ROOT}/python/${latest}/app.conf"
    if [[ ! -f "${old_conf}" ]]; then
        log_warn "No app.conf found at python/${latest}/app.conf; skipping app.conf generation"
        return
    fi

    local old_version="${latest}"
    local old_nodot="${old_version//./}"
    local new_nodot="${new_version//./}"
    local old_esc
    old_esc=$(sed_escape "${old_version}")

    cp "${old_conf}" "${new_conf}"

    sed -i \
        -e "s/Python ${old_esc}/Python ${new_version}/g" \
        -e "s/python-${old_esc}/python-${new_version}/g" \
        -e "s/^IMAGE_TAG=py${old_nodot}/IMAGE_TAG=py${new_nodot}/" \
        -e "s/^PYTHON_VERSION=${old_esc}/PYTHON_VERSION=${new_version}/" \
        -e "s/^PYTHON_VERSION_NODOT=${old_nodot}/PYTHON_VERSION_NODOT=${new_nodot}/" \
        -e "s|python-${old_nodot}|python-${new_nodot}|g" \
        "${new_conf}"

    # Strip digest and leave a TODO — new version will have a different digest
    sed -i '/^BASE_IMAGE=/i # TODO: pin digest for reproducible builds' "${new_conf}"
    sed -i 's/^\(BASE_IMAGE=.*\)@sha256:[a-f0-9]\+/\1/' "${new_conf}"

    log_info "Generated: ${new_conf} (from python/${old_version}/app.conf)"
}

# Create a starter app.conf for a new CUDA version
create_cuda_appconf() {
    local new_version="$1"
    local output_dir="$2"
    local new_conf="${output_dir}/app.conf"

    local latest
    latest=$(find_latest_version "cuda" "${new_version}") || {
        log_warn "No existing cuda version found; skipping app.conf generation"
        log_warn "Create ${output_dir}/app.conf manually"
        return
    }

    local old_conf="${PROJECT_ROOT}/cuda/${latest}/app.conf"
    if [[ ! -f "${old_conf}" ]]; then
        log_warn "No app.conf found at cuda/${latest}/app.conf; skipping app.conf generation"
        return
    fi

    local old_version="${latest}"
    local old_major="${old_version%%.*}"
    local old_minor="${old_version#*.}"
    local old_major_minor="${old_major}-${old_minor}"
    local old_esc
    old_esc=$(sed_escape "${old_version}")

    local new_major="${new_version%%.*}"
    local new_minor="${new_version#*.}"
    local new_major_minor="${new_major}-${new_minor}"

    cp "${old_conf}" "${new_conf}"

    # Update derivable version fields
    sed -i \
        -e "s/CUDA ${old_esc}/CUDA ${new_version}/g" \
        -e "s/cuda-${old_esc}/cuda-${new_version}/g" \
        -e "s/^IMAGE_TAG=${old_esc}/IMAGE_TAG=${new_version}/" \
        -e "s/^CUDA_MAJOR=${old_major}$/CUDA_MAJOR=${new_major}/" \
        -e "s/^CUDA_MAJOR_MINOR=${old_major_minor}$/CUDA_MAJOR_MINOR=${new_major_minor}/" \
        -e "s/^CUDA_MAJOR_MINOR_DOT=${old_esc}$/CUDA_MAJOR_MINOR_DOT=${new_version}/" \
        "${new_conf}"

    # Update dist path references in Source URLs (e.g., dist/12.8.1 -> dist/<new>.x)
    sed -i \
        -e "s|dist/${old_esc}\.[0-9]*|dist/${new_version}.x|g" \
        "${new_conf}"

    # Strip digest and leave a TODO
    sed -i '/^BASE_IMAGE=/i # TODO: pin digest for reproducible builds' "${new_conf}"
    sed -i 's/^\(BASE_IMAGE=.*\)@sha256:[a-f0-9]\+/\1/' "${new_conf}"

    # Mark NVIDIA-specific version lines with TODO comments
    local nvidia_keys=(
        CUDA_VERSION
        NV_CUDA_CUDART_VERSION
        NV_CUDA_LIB_VERSION
        NV_NVTX_VERSION
        NVIDIA_REQUIRE_CUDA
        NV_LIBCUBLAS_VERSION
        NV_LIBNPP_VERSION
        NV_LIBNCCL_VERSION
        NV_LIBNCCL_PACKAGE_VERSION
        NV_CUDNN_VERSION
    )
    for key in "${nvidia_keys[@]}"; do
        # Add TODO comment before each NVIDIA-specific key (if not already present)
        if grep -q "^${key}=" "${new_conf}" && ! grep -B1 "^${key}=" "${new_conf}" | grep -q "# TODO: update from NVIDIA"; then
            sed -i "/^${key}=/s/^/# TODO: update from NVIDIA\n/" "${new_conf}"
        fi
    done

    log_info "Generated: ${new_conf} (from cuda/${old_version}/app.conf)"
    log_warn "NVIDIA-specific version values are marked with TODO and must be updated"
    log_warn "See: https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist/${new_version}.x"
}

print_usage() {
    echo "Usage: $0 <cuda|python> <version>"
    echo ""
    echo "Generate a version-specific Containerfile and starter app.conf from template."
    echo ""
    echo "Arguments:"
    echo "  cuda <version>    Generate CUDA Containerfile + app.conf (e.g., 12.9, 13.0)"
    echo "  python <version>  Generate Python Containerfile + app.conf (e.g., 3.12, 3.13)"
    echo ""
    echo "Examples:"
    echo "  $0 cuda 12.9      # Generate cuda/12.9/{Containerfile,app.conf}"
    echo "  $0 cuda 13.0      # Generate cuda/13.0/{Containerfile,app.conf}"
    echo "  $0 python 3.13    # Generate python/3.13/{Containerfile,app.conf}"
}

generate_cuda() {
    local version="$1"

    # Validate version format
    validate_version "${version}" "cuda"

    local output_dir="${PROJECT_ROOT}/cuda/${version}"
    local template="${PROJECT_ROOT}/Containerfile.cuda.template"
    local output="${output_dir}/Containerfile"

    if [[ ! -f "${template}" ]]; then
        log_error "Template not found: ${template}"
        exit 1
    fi

    # Check if version already exists
    check_existing_version "${output_dir}" "${version}" "cuda"

    mkdir -p "${output_dir}"

    cp "${template}" "${output}"
    log_info "Generated: ${output}"

    create_cuda_appconf "${version}" "${output_dir}"

    log_info ""
    log_info "Next steps:"
    log_info "  1. Update NVIDIA-specific versions in cuda/${version}/app.conf"
    log_info "     (lines marked with '# TODO: update from NVIDIA')"
    log_info "  2. Get version values from NVIDIA:"
    log_info "     https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist/${version}.x"
    log_info "  3. Pin the BASE_IMAGE digest"
    log_info "  4. Build and test: ./scripts/build.sh cuda-${version}"
}

generate_python() {
    local version="$1"

    # Validate version format
    validate_version "${version}" "python"

    local output_dir="${PROJECT_ROOT}/python/${version}"
    local template="${PROJECT_ROOT}/Containerfile.python.template"
    local output="${output_dir}/Containerfile"

    if [[ ! -f "${template}" ]]; then
        log_error "Template not found: ${template}"
        exit 1
    fi

    # Check if version already exists
    check_existing_version "${output_dir}" "${version}" "python"

    mkdir -p "${output_dir}"

    cp "${template}" "${output}"
    log_info "Generated: ${output}"

    create_python_appconf "${version}" "${output_dir}"

    log_info ""
    log_info "Next steps:"
    log_info "  1. Review python/${version}/app.conf and verify version strings"
    log_info "  2. Pin the BASE_IMAGE digest"
    log_info "  3. Build and test: ./scripts/build.sh python-${version}"
}

main() {
    # Handle help flags first (before arg count check)
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
        print_usage
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        log_error "Missing arguments"
        print_usage
        exit 1
    fi

    local type="$1"
    local version="$2"

    case "${type}" in
        cuda)
            generate_cuda "${version}"
            ;;
        python)
            generate_python "${version}"
            ;;
        *)
            log_error "Unknown type: ${type}"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
