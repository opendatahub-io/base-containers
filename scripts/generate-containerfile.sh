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

# Global options (set by main via flag parsing)
TORCH_BACKEND=""
SKIP_PYTORCH_CHECK=false

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
        rocm)
            local major="${version%%.*}"
            if [[ "${major}" -lt 5 ]]; then
                log_warn "ROCm version ${version} is older than 5.x - are you sure?"
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

# Check if a PyTorch wheel index exists for a given CUDA backend (e.g., cu128, cu130).
# Returns 0 if the index exists (HTTP 200), 1 otherwise.
check_pytorch_wheel_index() {
    local backend="$1"
    local url="https://download.pytorch.org/whl/${backend}/"
    local http_code

    local curl_stderr
    curl_stderr=$(mktemp)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${url}" 2>"${curl_stderr}") || {
        log_error "Network error: could not reach ${url}"
        [[ -s "${curl_stderr}" ]] && log_error "curl: $(cat "${curl_stderr}")"
        rm -f "${curl_stderr}"
        log_error "Check your internet connection or re-run with --skip-pytorch-check"
        return 1
    }
    rm -f "${curl_stderr}"

    if [[ "${http_code}" == "200" ]]; then
        return 0
    else
        return 1
    fi
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
        NV_CUDA_CUPTI_VERSION
        NV_LIBCUSPARSELT_VERSION
        NV_LIBCUDSS_VERSION
    )
    for key in "${nvidia_keys[@]}"; do
        # Add TODO comment before each NVIDIA-specific key (if not already present)
        if grep -q "^${key}=" "${new_conf}" && ! grep -B1 "^${key}=" "${new_conf}" | grep -q "# TODO: update from NVIDIA"; then
            sed -i "/^${key}=/s/^/# TODO: update from NVIDIA\n/" "${new_conf}"
        fi
    done

    # Validate and update PyTorch wheel index for the new CUDA version
    local new_torch_backend
    if [[ -n "${TORCH_BACKEND}" ]]; then
        new_torch_backend="${TORCH_BACKEND}"
        log_info "Using user-specified torch backend: ${new_torch_backend}"
    else
        new_torch_backend="cu${new_major}${new_minor}"
    fi
    local new_torch_index="https://download.pytorch.org/whl/${new_torch_backend}"

    if [[ "${SKIP_PYTORCH_CHECK}" == "true" && -z "${TORCH_BACKEND}" ]]; then
        log_error "--skip-pytorch-check requires --torch-backend to avoid using an"
        log_error "auto-derived backend that may not exist (e.g., cu131 for CUDA 13.1"
        log_error "when PyTorch only publishes cu130)."
        log_error ""
        log_error "Example: $0 cuda ${new_version} --skip-pytorch-check --torch-backend cu${new_major}${new_minor}"
        exit 1
    elif [[ "${SKIP_PYTORCH_CHECK}" == "true" ]]; then
        log_warn "Skipping PyTorch wheel index check (--skip-pytorch-check)"
        log_warn "Using backend ${new_torch_backend} without online validation"
    else
        log_info "Checking PyTorch wheel index for ${new_torch_backend}..."
        if ! check_pytorch_wheel_index "${new_torch_backend}"; then
            log_error "No PyTorch wheel index found for ${new_torch_backend}"
            log_error "URL checked: ${new_torch_index}/"
            log_error "PyTorch does not publish wheels for every CUDA minor version."
            log_error "Check available indexes at: https://download.pytorch.org/whl/"
            log_error ""
            log_error "To use an older CUDA wheel index, re-run with:"
            log_error "  $0 cuda ${new_version} --torch-backend <backend>"
            log_error "  Example: $0 cuda ${new_version} --torch-backend cu${new_major}$((new_minor > 0 ? new_minor - 1 : 0))"
            log_error ""
            log_error "To skip this check entirely (offline/air-gapped), re-run with:"
            log_error "  $0 cuda ${new_version} --skip-pytorch-check --torch-backend <backend>"
            # Clean up only the files created by this run
            rm -f "${new_conf}" "${output_dir}/Containerfile"
            rmdir "${output_dir}" 2>/dev/null || true
            exit 1
        fi
        log_info "PyTorch wheel index found: ${new_torch_index}"
    fi

    # Update PIP_EXTRA_INDEX_URL and UV_TORCH_BACKEND in app.conf
    sed -i "s|^PIP_EXTRA_INDEX_URL=.*|PIP_EXTRA_INDEX_URL=${new_torch_index}|" "${new_conf}"
    sed -i "s|^UV_TORCH_BACKEND=.*|UV_TORCH_BACKEND=${new_torch_backend}|" "${new_conf}"
    log_info "Updated PIP_EXTRA_INDEX_URL to ${new_torch_index}"
    log_info "Updated UV_TORCH_BACKEND to ${new_torch_backend}"

    log_info "Generated: ${new_conf} (from cuda/${old_version}/app.conf)"
    log_warn "NVIDIA-specific version values are marked with TODO and must be updated"
    log_warn "See: https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist/${new_version}.x"
}

# Create a starter app.conf for a new ROCm version
create_rocm_appconf() {
    local new_version="$1"
    local output_dir="$2"
    local new_conf="${output_dir}/app.conf"

    local latest
    latest=$(find_latest_version "rocm" "${new_version}") || {
        log_warn "No existing rocm version found; skipping app.conf generation"
        log_warn "Create ${output_dir}/app.conf manually"
        return
    }

    local old_conf="${PROJECT_ROOT}/rocm/${latest}/app.conf"
    if [[ ! -f "${old_conf}" ]]; then
        log_warn "No app.conf found at rocm/${latest}/app.conf; skipping app.conf generation"
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
        -e "s/ROCm ${old_esc}/ROCm ${new_version}/g" \
        -e "s/rocm-${old_esc}/rocm-${new_version}/g" \
        -e "s/^IMAGE_TAG=${old_esc}/IMAGE_TAG=${new_version}/" \
        -e "s/^ROCM_MAJOR=${old_major}$/ROCM_MAJOR=${new_major}/" \
        -e "s/^ROCM_MAJOR_MINOR=${old_major_minor}$/ROCM_MAJOR_MINOR=${new_major_minor}/" \
        -e "s/^ROCM_MAJOR_MINOR_DOT=${old_esc}$/ROCM_MAJOR_MINOR_DOT=${new_version}/" \
        "${new_conf}"

    # Update repo path references (e.g., el9/6.4.3 -> el9/<new>.x)
    sed -i \
        -e "s|el9/${old_esc}\.[0-9]*|el9/${new_version}.x|g" \
        "${new_conf}"

    # Strip digest and leave a TODO
    sed -i '/^BASE_IMAGE=/i # TODO: pin digest for reproducible builds' "${new_conf}"
    sed -i 's/^\(BASE_IMAGE=.*\)@sha256:[a-f0-9]\+/\1/' "${new_conf}"

    # Mark ROCm-specific version lines with TODO comments
    local rocm_keys=(
        ROCM_VERSION
    )
    for key in "${rocm_keys[@]}"; do
        if grep -q "^${key}=" "${new_conf}" && ! grep -B1 "^${key}=" "${new_conf}" | grep -q "# TODO: update from AMD"; then
            sed -i "/^${key}=/s/^/# TODO: update from AMD\n/" "${new_conf}"
        fi
    done

    # Validate and update PyTorch wheel index for the new ROCm version
    local new_torch_backend
    if [[ -n "${TORCH_BACKEND}" ]]; then
        new_torch_backend="${TORCH_BACKEND}"
        log_info "Using user-specified torch backend: ${new_torch_backend}"
    else
        new_torch_backend="rocm${new_version}"
    fi
    local new_torch_index="https://download.pytorch.org/whl/${new_torch_backend}"

    if [[ "${SKIP_PYTORCH_CHECK}" == "true" && -z "${TORCH_BACKEND}" ]]; then
        log_error "--skip-pytorch-check requires --torch-backend to avoid using an"
        log_error "auto-derived backend that may not exist."
        log_error ""
        log_error "Example: $0 rocm ${new_version} --skip-pytorch-check --torch-backend rocm${new_version}"
        exit 1
    elif [[ "${SKIP_PYTORCH_CHECK}" == "true" ]]; then
        log_warn "Skipping PyTorch wheel index check (--skip-pytorch-check)"
        log_warn "Using backend ${new_torch_backend} without online validation"
    else
        log_info "Checking PyTorch wheel index for ${new_torch_backend}..."
        if ! check_pytorch_wheel_index "${new_torch_backend}"; then
            log_error "No PyTorch wheel index found for ${new_torch_backend}"
            log_error "URL checked: ${new_torch_index}/"
            log_error "PyTorch does not publish wheels for every ROCm version."
            log_error "Check available indexes at: https://download.pytorch.org/whl/"
            log_error ""
            log_error "To use a different ROCm wheel index, re-run with:"
            log_error "  $0 rocm ${new_version} --torch-backend <backend>"
            log_error "  Example: $0 rocm ${new_version} --torch-backend rocm${old_version}"
            log_error ""
            log_error "To skip this check entirely (offline/air-gapped), re-run with:"
            log_error "  $0 rocm ${new_version} --skip-pytorch-check --torch-backend <backend>"
            # Clean up only the files created by this run
            rm -f "${new_conf}" "${output_dir}/Containerfile"
            rmdir "${output_dir}" 2>/dev/null || true
            exit 1
        fi
        log_info "PyTorch wheel index found: ${new_torch_index}"
    fi

    # Update PIP_EXTRA_INDEX_URL and UV_TORCH_BACKEND in app.conf
    sed -i "s|^PIP_EXTRA_INDEX_URL=.*|PIP_EXTRA_INDEX_URL=${new_torch_index}|" "${new_conf}"
    sed -i "s|^UV_TORCH_BACKEND=.*|UV_TORCH_BACKEND=${new_torch_backend}|" "${new_conf}"
    log_info "Updated PIP_EXTRA_INDEX_URL to ${new_torch_index}"
    log_info "Updated UV_TORCH_BACKEND to ${new_torch_backend}"

    log_info "Generated: ${new_conf} (from rocm/${old_version}/app.conf)"
    log_warn "ROCm-specific version values are marked with TODO and must be updated"
    log_warn "See: https://repo.radeon.com/rocm/el9/${new_version}.x/"
}

print_usage() {
    echo "Usage: $0 <cuda|rocm|python> <version> [options]"
    echo ""
    echo "Generate a version-specific Containerfile and starter app.conf from template."
    echo ""
    echo "Arguments:"
    echo "  cuda <version>    Generate CUDA Containerfile + app.conf (e.g., 12.9, 13.0)"
    echo "  rocm <version>    Generate ROCm Containerfile + app.conf (e.g., 6.4, 7.1)"
    echo "  python <version>  Generate Python Containerfile + app.conf (e.g., 3.12, 3.13)"
    echo ""
    echo "Options (cuda and rocm):"
    echo "  --torch-backend <backend>  Use a specific PyTorch backend (e.g., cu128, rocm6.4)"
    echo "                             instead of auto-deriving from the version."
    echo "                             Useful when PyTorch doesn't publish wheels for every"
    echo "                             minor version (e.g., CUDA 13.1 uses cu130)."
    echo "  --skip-pytorch-check       Skip the PyTorch wheel index HTTP validation."
    echo "                             Requires --torch-backend to avoid silently using"
    echo "                             an incorrect auto-derived backend."
    echo ""
    echo "Examples:"
    echo "  $0 cuda 12.9                          # Auto-derives cu129, validates online"
    echo "  $0 cuda 13.1 --torch-backend cu130    # Use cu130 for CUDA 13.1"
    echo "  $0 cuda 13.2 --skip-pytorch-check --torch-backend cu132  # Skip online check (offline)"
    echo "  $0 rocm 7.1                           # Auto-derives rocm7.1, validates online"
    echo "  $0 rocm 7.1 --torch-backend rocm7.0   # Use rocm7.0 for ROCm 7.1"
    echo "  $0 python 3.13                        # Generate python/3.13/{Containerfile,app.conf}"
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

generate_rocm() {
    local version="$1"

    # Validate version format
    validate_version "${version}" "rocm"

    local output_dir="${PROJECT_ROOT}/rocm/${version}"
    local template="${PROJECT_ROOT}/Containerfile.rocm.template"
    local output="${output_dir}/Containerfile"

    if [[ ! -f "${template}" ]]; then
        log_error "Template not found: ${template}"
        exit 1
    fi

    # Check if version already exists
    check_existing_version "${output_dir}" "${version}" "rocm"

    mkdir -p "${output_dir}"

    cp "${template}" "${output}"
    log_info "Generated: ${output}"

    create_rocm_appconf "${version}" "${output_dir}"

    log_info ""
    log_info "Next steps:"
    log_info "  1. Update ROCm-specific versions in rocm/${version}/app.conf"
    log_info "     (lines marked with '# TODO: update from AMD')"
    log_info "  2. Get version values from AMD:"
    log_info "     https://repo.radeon.com/rocm/el9/${version}.x/"
    log_info "  3. Pin the BASE_IMAGE digest"
    log_info "  4. Build and test: ./scripts/build.sh rocm-${version}"
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
    shift 2

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --torch-backend)
                if [[ $# -lt 2 ]]; then
                    log_error "--torch-backend requires a value (e.g., cu128, cu130)"
                    exit 1
                fi
                TORCH_BACKEND="$2"
                if [[ ! "${TORCH_BACKEND}" =~ ^(cu[0-9]+|rocm[0-9]+\.[0-9]+)$ ]]; then
                    log_error "Invalid torch backend format: '${TORCH_BACKEND}'"
                    log_error "Expected format: cu<digits> (e.g., cu128) or rocm<major>.<minor> (e.g., rocm6.4)"
                    exit 1
                fi
                shift 2
                ;;
            --skip-pytorch-check)
                SKIP_PYTORCH_CHECK=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    case "${type}" in
        cuda)
            generate_cuda "${version}"
            ;;
        rocm)
            generate_rocm "${version}"
            ;;
        python)
            if [[ -n "${TORCH_BACKEND}" || "${SKIP_PYTORCH_CHECK}" == "true" ]]; then
                log_warn "--torch-backend and --skip-pytorch-check are ignored for python images"
            fi
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
