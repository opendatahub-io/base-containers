"""Tests specific to the Python base image.

These tests verify Python-specific labels and configurations
that differ from the CUDA image.
"""

import os

# --- OCI Label Tests ---


def test_name_label(python_container):
    """Verify name label is set."""
    labels = python_container.get_labels()
    assert labels.get("name"), "name label should be set and non-empty"


def test_version_label(python_container):
    """Verify version label is set."""
    labels = python_container.get_labels()
    assert labels.get("version"), "version label should be set and non-empty"


def test_k8s_display_name_label(python_container):
    """Verify Kubernetes display name label is set."""
    labels = python_container.get_labels()
    assert labels.get("io.k8s.display-name"), "Kubernetes display name label should be set"


def test_opencontainers_source_label(python_container):
    """Verify OCI source label points to GitHub."""
    labels = python_container.get_labels()
    source = labels.get("org.opencontainers.image.source", "")
    assert source, "OCI source label should be set"
    assert "github.com" in source, f"OCI source should point to GitHub, got: {source}"


def test_accelerator_label_cpu(python_container):
    """Verify accelerator label is 'cpu' for Python image."""
    labels = python_container.get_labels()
    accelerator = labels.get("com.opendatahub.accelerator")
    assert accelerator == "cpu", f"Expected accelerator='cpu', got: {accelerator}"


def test_python_version_label(python_container):
    """Verify Python version label matches expected version.

    The expected version is controlled by the PYTHON_VERSION environment variable.
    If not set, defaults to 3.12 for backward compatibility.
    """
    expected_version = os.environ.get("PYTHON_VERSION", "3.12")
    labels = python_container.get_labels()
    python_version = labels.get("com.opendatahub.python", "")
    assert python_version, "Python version label should be set"
    assert expected_version in python_version, (
        f"Expected Python version label to contain {expected_version}, got: {python_version}"
    )
