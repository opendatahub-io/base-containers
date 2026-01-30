#!/bin/bash
# =============================================================================
# ODH Base Containers - Build Script
# =============================================================================
# Usage: ./scripts/build.sh [target]
#
# Targets:
#   cuda-12.8, cuda-12.9, cuda-13.0, cuda-13.1  - Build specific CUDA version
#   python-3.12                                  - Build specific Python version
#   cuda                                         - Build all CUDA versions
#   python                                       - Build all Python versions
#   all                                          - Build everything (default)
#
# Environment Variables:
#   IMAGE_REGISTRY    - Registry prefix (default: quay.io/opendatahub)
#   PUSH_IMAGES       - Push after build (default: false)
#
# Note: Requires podman/buildah (uses --build-arg-file, not supported by docker)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_REGISTRY="${IMAGE_REGISTRY:-quay.io/opendatahub}"
PUSH_IMAGES="${PUSH_IMAGES:-false}"

# Require podman/buildah (--build-arg-file not supported by docker)
if ! command -v podman &> /dev/null; then
    echo "Error: podman is required (--build-arg-file not supported by docker)" >&2
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Detect target architecture (maps uname -m to OCI arch names)
get_target_arch() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "${arch}" ;;
    esac
}

get_config_value() {
    local config_file="$1"
    local key="$2"
    grep "^${key}=" "${config_file}" 2>/dev/null | cut -d'=' -f2- || true
}

# Get all available versions for a given type (cuda or python)
get_all_versions() {
    local type="$1"
    local type_dir="${PROJECT_ROOT}/${type}"

    if [[ ! -d "${type_dir}" ]]; then
        return
    fi

    # Find all version directories and sort them
    find "${type_dir}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -V
}

# Build a versioned image (cuda or python)
build_versioned_image() {
    local type="$1"      # cuda or python
    local version="$2"   # e.g., 12.8 or 3.12
    local config_file="${PROJECT_ROOT}/${type}/${version}/app.conf"
    local containerfile="${PROJECT_ROOT}/${type}/${version}/Containerfile"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Config file not found: ${config_file}"
        exit 1
    fi

    if [[ ! -f "${containerfile}" ]]; then
        log_error "Containerfile not found: ${containerfile}"
        exit 1
    fi

    local image_tag
    image_tag=$(get_config_value "${config_file}" "IMAGE_TAG")
    if [[ -z "${image_tag}" ]]; then
        log_error "IMAGE_TAG not defined in ${config_file}"
        exit 1
    fi

    local image_name="${IMAGE_REGISTRY}/odh-midstream-${type}-base"
    local full_image="${image_name}:${image_tag}"

    local target_arch
    target_arch=$(get_target_arch)

    log_info "Building ${type} ${version} base image: ${full_image}"
    log_info "  Config: ${config_file}"
    log_info "  Containerfile: ${containerfile}"
    log_info "  Arch: ${target_arch}"

    podman build \
        --build-arg-file "${config_file}" \
        --build-arg BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
        --build-arg TARGETARCH="${target_arch}" \
        -t "${full_image}" \
        -f "${containerfile}" \
        "${PROJECT_ROOT}"

    log_info "Successfully built: ${full_image}"

    if [[ "${PUSH_IMAGES}" == "true" ]]; then
        log_info "Pushing: ${full_image}"
        podman push "${full_image}"
    fi
}

# Build all versions of a given type
build_all_of_type() {
    local type="$1"
    local versions
    versions=$(get_all_versions "${type}")

    if [[ -z "${versions}" ]]; then
        log_warn "No ${type} versions found in ${PROJECT_ROOT}/${type}/"
        return
    fi

    log_info "Building all ${type} versions: ${versions//$'\n'/, }"

    for version in ${versions}; do
        build_versioned_image "${type}" "${version}"
    done
}

print_usage() {
    echo "Usage: $0 [target]"
    echo ""
    echo "Build ODH base container images."
    echo ""
    echo "Targets:"
    echo "  cuda-<version>    - Build specific CUDA version (e.g., cuda-12.8, cuda-13.0)"
    echo "  python-<version>  - Build specific Python version (e.g., python-3.12)"
    echo "  cuda              - Build all CUDA versions"
    echo "  python            - Build all Python versions"
    echo "  all               - Build all images (default)"
    echo ""
    echo "Available CUDA versions:"
    local cuda_versions
    cuda_versions=$(get_all_versions "cuda")
    if [[ -n "${cuda_versions}" ]]; then
        for v in ${cuda_versions}; do
            echo "    cuda-${v}"
        done
    else
        echo "    (none found)"
    fi
    echo ""
    echo "Available Python versions:"
    local python_versions
    python_versions=$(get_all_versions "python")
    if [[ -n "${python_versions}" ]]; then
        for v in ${python_versions}; do
            echo "    python-${v}"
        done
    else
        echo "    (none found)"
    fi
    echo ""
    echo "Environment Variables:"
    echo "  IMAGE_REGISTRY    - Registry prefix (default: quay.io/opendatahub)"
    echo "  PUSH_IMAGES       - Push after build (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 cuda-12.8      # Build CUDA 12.8 only"
    echo "  $0 cuda-13.0      # Build CUDA 13.0 only"
    echo "  $0 cuda           # Build all CUDA versions"
    echo "  $0 python-3.12    # Build Python 3.12 only"
    echo "  $0 python         # Build all Python versions"
    echo "  $0 all            # Build everything"
    echo ""
    echo "Note: Requires podman (uses --build-arg-file, not supported by docker)"
}

main() {
    local target="${1:-all}"

    log_info "=== ODH Base Containers Build ==="
    echo "  Image Registry: ${IMAGE_REGISTRY}"
    echo "  Push Images:    ${PUSH_IMAGES}"
    echo "=================================="

    case "${target}" in
        # Specific CUDA version (cuda-12.8, cuda-13.0, etc.)
        cuda-*)
            local version="${target#cuda-}"
            if [[ ! -d "${PROJECT_ROOT}/cuda/${version}" ]]; then
                log_error "CUDA version ${version} not found in ${PROJECT_ROOT}/cuda/"
                log_info "Available versions: $(get_all_versions cuda | tr '\n' ' ')"
                exit 1
            fi
            build_versioned_image "cuda" "${version}"
            ;;

        # Specific Python version (python-3.12, etc.)
        python-*)
            local version="${target#python-}"
            if [[ ! -d "${PROJECT_ROOT}/python/${version}" ]]; then
                log_error "Python version ${version} not found in ${PROJECT_ROOT}/python/"
                log_info "Available versions: $(get_all_versions python | tr '\n' ' ')"
                exit 1
            fi
            build_versioned_image "python" "${version}"
            ;;

        # All CUDA versions
        cuda)
            build_all_of_type "cuda"
            ;;

        # All Python versions
        python)
            build_all_of_type "python"
            ;;

        # Everything
        all)
            build_all_of_type "python"
            build_all_of_type "cuda"
            ;;

        -h|--help|help)
            print_usage
            exit 0
            ;;

        *)
            log_error "Unknown target: ${target}"
            print_usage
            exit 1
            ;;
    esac

    log_info "Build completed successfully!"
}

main "$@"
