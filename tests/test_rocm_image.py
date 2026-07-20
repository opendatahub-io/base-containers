"""Tests specific to the ROCm base image.

These tests verify ROCm-specific environment variables, libraries,
and labels. All tests run without GPU hardware.
"""

import os
import re

import pytest

# --- ROCm Environment Tests ---


def test_rocm_version(rocm_container):
    """Verify ROCM_VERSION environment variable matches expected version.

    The expected version is controlled by the ROCM_VERSION environment variable.
    If not set, version validation is skipped (only checks env var exists).
    """
    actual_version = rocm_container.get_env("ROCM_VERSION")
    assert actual_version, "ROCM_VERSION environment variable should be set in container"

    expected_version = os.environ.get("ROCM_VERSION")
    if expected_version is None:
        pytest.skip(
            "ROCM_VERSION not set - skipping version validation. "
            "Set ROCM_VERSION env var to validate specific version."
        )
    assert actual_version.startswith(expected_version), (
        f"Expected ROCM_VERSION to start with {expected_version}, got {actual_version}"
    )


def test_rocm_home(rocm_container):
    """Verify ROCM_HOME points to the ROCm installation directory.

    PyTorch and other ML frameworks use ROCM_HOME to locate the ROCm toolkit.
    ROCm <= 7.2 uses /opt/rocm; ROCm 7.14+ (TheRock) uses /opt/rocm/core.
    """
    rocm_home = rocm_container.get_env("ROCM_HOME")
    assert rocm_home in ("/opt/rocm", "/opt/rocm/core"), (
        f"Expected ROCM_HOME to be /opt/rocm or /opt/rocm/core, got {rocm_home}"
    )


def test_rocm_in_path(rocm_container):
    """Verify ROCm bin directory is in PATH."""
    path = rocm_container.get_env("PATH")
    rocm_home = rocm_container.get_env("ROCM_HOME") or "/opt/rocm"
    assert f"{rocm_home}/bin" in path, f"Expected {rocm_home}/bin in PATH, got {path}"


# --- ROCm Directory Tests ---


def test_rocm_dir_exists(rocm_container):
    """Verify ROCm installation directory exists."""
    assert rocm_container.dir_exists("/opt/rocm")


# --- ROCm Library Tests ---


def test_libamdhip64_present(rocm_container):
    """Verify HIP runtime library is present.

    Core AMD HIP runtime library, equivalent to CUDA's libcudart.
    Installed via hip-runtime-amd package.
    """
    result = rocm_container.run("ldconfig -p | grep libamdhip64")
    assert result.returncode == 0, (
        "libamdhip64.so not found - hip-runtime-amd package may be missing"
    )


def test_librocblas_present(rocm_container):
    """Verify rocBLAS library is present.

    BLAS library for AMD GPUs, equivalent to CUDA's libcublas.
    Installed via rocblas package.
    """
    result = rocm_container.run("ldconfig -p | grep librocblas")
    assert result.returncode == 0, "librocblas.so not found - rocblas package may be missing"


def test_librccl_present(rocm_container):
    """Verify RCCL (ROCm Communication Collectives Library) is present.

    Required for multi-GPU and distributed training with PyTorch.
    Equivalent to NVIDIA's NCCL. Installed via rccl package.
    """
    result = rocm_container.run("ldconfig -p | grep librccl")
    assert result.returncode == 0, "librccl.so not found - rccl package may be missing"


def test_libMIOpen_present(rocm_container):
    """Verify MIOpen library is present.

    AMD's deep learning primitives library, equivalent to CUDA's cuDNN.
    Installed via miopen-hip package.
    """
    result = rocm_container.run("ldconfig -p | grep libMIOpen")
    assert result.returncode == 0, "libMIOpen.so not found - miopen-hip package may be missing"


def test_librocfft_present(rocm_container):
    """Verify rocFFT library is present.

    FFT library for AMD GPUs. Installed via rocfft package.
    """
    result = rocm_container.run("ldconfig -p | grep librocfft")
    assert result.returncode == 0, "librocfft.so not found - rocfft package may be missing"


def test_librocsolver_present(rocm_container):
    """Verify rocSOLVER library is present.

    Linear algebra solver library for AMD GPUs.
    Installed via rocsolver package.
    """
    result = rocm_container.run("ldconfig -p | grep librocsolver")
    assert result.returncode == 0, "librocsolver.so not found - rocsolver package may be missing"


# --- ROCm Label Tests ---


def test_rocm_version_label(rocm_container):
    """Verify ROCm version label is present."""
    assert "com.amd.rocm.version" in rocm_container.get_labels()


def test_uv_torch_backend(rocm_container):
    """Verify torch-backend is configured in uv.toml for ROCm wheel selection.

    Uses a specific backend (e.g. rocm6.4) rather than "auto" because
    auto detects GPU drivers at runtime, which are absent during container builds.
    Configured via uv.toml (not ENV) to avoid uv erroring on empty values.

    ROCm 7.14+: uv does not yet support rocm7.14 as a torch-backend value,
    so torch-backend may be absent. Test is skipped in that case.
    """
    result = rocm_container.run("cat /etc/uv/uv.toml")
    assert result.returncode == 0, "Failed to read /etc/uv/uv.toml"

    if "torch-backend" not in result.stdout:
        pytest.skip(
            "torch-backend not configured (expected for ROCm versions not yet supported by uv)"
        )

    match = re.search(r'torch-backend\s*=\s*"(rocm\d+\.\d+)"', result.stdout)
    assert match, f'Expected torch-backend = "rocmX.Y" in uv.toml, got:\n{result.stdout}'
    expected_backend = os.environ.get("UV_TORCH_BACKEND")
    if expected_backend is not None:
        assert match.group(1) == expected_backend, (
            f'Expected torch-backend = "{expected_backend}", got "{match.group(1)}"'
        )


def test_accelerator_label_rocm(rocm_container):
    """Verify accelerator label is 'rocm' for ROCm image."""
    assert rocm_container.get_labels().get("com.opendatahub.accelerator") == "rocm"
