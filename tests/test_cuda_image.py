"""Tests specific to the CUDA base image.

These tests verify CUDA-specific environment variables, libraries,
and labels. All tests run without GPU hardware.
"""


# --- CUDA Environment Tests ---


def test_cuda_version(cuda_container):
    """Verify CUDA_VERSION environment variable is set to 12.8.x."""
    assert cuda_container.get_env("CUDA_VERSION").startswith("12.8")


def test_nvidia_visible_devices(cuda_container):
    """Verify NVIDIA_VISIBLE_DEVICES is set to 'all'."""
    assert cuda_container.get_env("NVIDIA_VISIBLE_DEVICES") == "all"


def test_cuda_in_path(cuda_container):
    """Verify CUDA bin directory is in PATH."""
    assert "/usr/local/cuda/bin" in cuda_container.get_env("PATH")


# --- CUDA Toolkit Tests ---


def test_nvcc_exists(cuda_container):
    """Verify nvcc compiler is installed."""
    result = cuda_container.run("which nvcc")
    assert result.returncode == 0
    assert "/usr/local/cuda" in result.stdout


def test_cuda_dir_exists(cuda_container):
    """Verify CUDA toolkit directory exists."""
    assert cuda_container.dir_exists("/usr/local/cuda")


# --- CUDA Library Tests ---


def test_libcudart_present(cuda_container):
    """Verify CUDA runtime library is present."""
    result = cuda_container.run("ldconfig -p | grep libcudart")
    assert result.returncode == 0


def test_libcublas_present(cuda_container):
    """Verify cuBLAS library is present."""
    result = cuda_container.run("ldconfig -p | grep libcublas")
    assert result.returncode == 0


def test_libcudnn_present(cuda_container):
    """Verify cuDNN library is present."""
    result = cuda_container.run("ldconfig -p | grep libcudnn")
    assert result.returncode == 0


# --- CUDA Label Tests ---


def test_cuda_version_label(cuda_container):
    """Verify CUDA version label is present."""
    assert "com.nvidia.cuda.version" in cuda_container.get_labels()


def test_accelerator_label_cuda(cuda_container):
    """Verify accelerator label is 'cuda' for CUDA image."""
    assert cuda_container.get_labels().get("com.opendatahub.accelerator") == "cuda"
