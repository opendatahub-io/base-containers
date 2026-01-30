#!/bin/bash
# =============================================================================
# Generate Containerfile from Template
# =============================================================================
#
# Generates a version-specific Containerfile from the template by replacing
# placeholder markers with actual version values.
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

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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
            log_warn "Directory ${type}/${version}/ already exists with a Containerfile"
            read -p "Overwrite? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Aborted"
                exit 0
            fi
        fi
    fi
}

print_usage() {
    echo "Usage: $0 <cuda|python> <version>"
    echo ""
    echo "Generate a version-specific Containerfile from template."
    echo ""
    echo "Arguments:"
    echo "  cuda <version>    Generate CUDA Containerfile (e.g., 12.9, 13.0)"
    echo "  python <version>  Generate Python Containerfile (e.g., 3.12, 3.13)"
    echo ""
    echo "Examples:"
    echo "  $0 cuda 12.9      # Generate cuda/12.9/Containerfile"
    echo "  $0 cuda 13.0      # Generate cuda/13.0/Containerfile"
    echo "  $0 python 3.13    # Generate python/3.13/Containerfile"
}

generate_cuda() {
    local version="$1"

    # Validate version format
    validate_version "${version}" "cuda"

    local major_minor="${version//./-}"           # 12.9 -> 12-9
    local major="${version%%.*}"                  # 12.9 -> 12
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

    sed -e "s/{{CUDA_MAJOR_MINOR}}/${major_minor}/g" \
        -e "s/{{CUDA_MAJOR_MINOR_DOT}}/${version}/g" \
        -e "s/{{CUDA_MAJOR}}/${major}/g" \
        "${template}" > "${output}"

    log_info "Generated: ${output}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Create ${output_dir}/app.conf with version-specific values"
    log_info "     (Use cuda/12.8/app.conf as a reference)"
    log_info "  2. Get version values from NVIDIA:"
    log_info "     https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist/${version}.x"
    log_info "  3. Build and test: ./scripts/build.sh cuda-${version}"
}

generate_python() {
    local version="$1"

    # Validate version format
    validate_version "${version}" "python"

    local version_nodot="${version//.}"           # 3.12 -> 312
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

    sed -e "s/{{PYTHON_VERSION}}/${version}/g" \
        -e "s/{{PYTHON_VERSION_NODOT}}/${version_nodot}/g" \
        "${template}" > "${output}"

    log_info "Generated: ${output}"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Create ${output_dir}/app.conf with version-specific values"
    log_info "     (Use python/3.12/app.conf as a reference)"
    log_info "  2. Update BASE_IMAGE to the appropriate UBI Python image"
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
