"""Common tests that apply to both Python and CUDA images.

These tests verify core functionality that should work identically
across all ODH base container images.
"""

import pytest

from tests import APP_ROOT, WORKDIR, redact_url_credentials


@pytest.fixture(params=["python_container", "cuda_container"])
def container(request):
    """Parameterize to run same tests against both images."""
    return request.getfixturevalue(request.param)


# --- Smoke Tests ---


def test_python_version(container):
    """Verify installed Python version matches the com.opendatahub.python label."""
    expected = container.get_labels().get("com.opendatahub.python", "")
    assert expected, "com.opendatahub.python label must be set"

    result = container.run("python --version")
    assert result.returncode == 0
    assert f"Python {expected}" in result.stdout, (
        f"Expected Python {expected} (from label), got: {result.stdout.strip()}"
    )


def test_pip_available(container):
    """Verify pip is installed and working."""
    result = container.run("pip --version")
    assert result.returncode == 0


def test_uv_available(container):
    """Verify uv package manager is installed and working."""
    result = container.run("uv --version")
    assert result.returncode == 0


def test_pip_install_dry_run(container):
    """Verify pip can resolve packages using the configured index-url.

    Uses --dry-run to avoid modifying container state (session-scoped containers are shared).
    A failure here indicates a broken index-url, missing CA certs, or malformed /etc/pip.conf.
    """
    result = container.run("pip install --dry-run --upgrade setuptools", timeout=60)
    assert result.returncode == 0, (
        "pip install --dry-run failed — broken index-url, missing CA certs, "
        f"or malformed /etc/pip.conf\nstderr: {redact_url_credentials(result.stderr)}"
    )


def test_uv_pip_compile_smoke(container):
    """Verify uv can resolve packages using the configured index-url.

    Uses uv pip compile reading from stdin to resolve without installing (read-only).
    A failure here indicates a broken index-url, missing CA certs, or malformed /etc/uv/uv.toml.
    """
    result = container.run("echo 'setuptools' | uv pip compile -", timeout=60)
    assert result.returncode == 0, (
        "uv pip compile failed — broken index-url, missing CA certs, "
        f"or malformed /etc/uv/uv.toml\nstderr: {redact_url_credentials(result.stderr)}"
    )


# --- User & Permission Tests ---


def test_user_id(container):
    """Verify container runs as UID 1001 for OpenShift compatibility."""
    result = container.run("id -u")
    assert result.returncode == 0
    assert result.stdout.strip() == "1001"


def test_group_id(container):
    """Verify container uses GID 0 (root group) for OpenShift compatibility."""
    result = container.run("id -g")
    assert result.returncode == 0
    assert result.stdout.strip() == "0"


def test_not_root(container):
    """Verify container does not run as root user."""
    result = container.run("whoami")
    assert result.returncode == 0
    assert result.stdout.strip() != "root"


def test_workdir_writable(container):
    """Verify working directory is writable by the container user."""
    result = container.run(f'f=$(mktemp {WORKDIR}/.writetest.XXXXXX) && rm "$f"')
    assert result.returncode == 0


def test_fix_permissions_executable(container):
    """Verify fix-permissions script is installed and executable.

    This script is critical for OpenShift compatibility, it ensures GID 0
    group write access on directories. If accidentally removed or with wrong
    permissions, downstream images break at runtime with permission errors.
    """
    assert container.file_executable("/usr/local/bin/fix-permissions"), (
        "/usr/local/bin/fix-permissions must exist and be executable"
    )


# --- Configuration Tests ---


def test_pip_conf_exists(container):
    """Verify pip configuration file exists."""
    assert container.file_exists("/etc/pip.conf"), "pip configuration file not found"


def test_pip_conf_valid(container):
    """Verify pip configuration contains global section."""
    result = container.run("cat /etc/pip.conf")
    assert "[global]" in result.stdout, "pip.conf missing [global] section"


def test_pip_index_url_configured(container):
    """Verify pip global.index-url is configured"""
    result = container.run("pip config --global get global.index-url")
    assert result.returncode == 0, (
        "pip global.index-url is not set — expected an index-url in /etc/pip.conf"
    )
    index_url = result.stdout.strip()
    assert index_url, "pip global.index-url is set but empty"


def test_uv_toml_exists(container):
    """Verify uv configuration file exists."""
    assert container.file_exists("/etc/uv/uv.toml"), "uv configuration file not found"


def test_uv_config_file_env(container):
    """Verify UV_CONFIG_FILE environment variable points to config."""
    assert container.get_env("UV_CONFIG_FILE") == "/etc/uv/uv.toml"


# --- Image Metadata Tests ---


def test_workdir(container):
    """Verify WORKDIR is set to /opt/app-root/src."""
    assert container.get_config("WorkingDir") == WORKDIR


def test_user(container):
    """Verify USER is set to 1001."""
    assert container.get_config("User") == "1001"


# --- Environment Variable Tests ---


def test_home(container):
    """Verify HOME is set to /opt/app-root/src."""
    assert container.get_env("HOME") == WORKDIR


def test_path_contains_app_root(container):
    """Verify PATH includes /opt/app-root/bin."""
    assert f"{APP_ROOT}/bin" in container.get_env("PATH")


def test_pythondontwritebytecode(container):
    """Verify PYTHONDONTWRITEBYTECODE=1 to avoid .pyc files."""
    assert container.get_env("PYTHONDONTWRITEBYTECODE") == "1"


def test_pythonunbuffered(container):
    """Verify PYTHONUNBUFFERED=1 for real-time logging."""
    assert container.get_env("PYTHONUNBUFFERED") == "1"


def test_pip_no_cache_dir(container):
    """Verify PIP_NO_CACHE_DIR=1 to reduce image size."""
    assert container.get_env("PIP_NO_CACHE_DIR") == "1"


def test_uv_system_python(container):
    """Verify UV_SYSTEM_PYTHON=1 for system Python usage."""
    assert container.get_env("UV_SYSTEM_PYTHON") == "1"


# --- OCI Label Tests ---


def test_name_label(container):
    """Verify name label is set."""
    labels = container.get_labels()
    assert labels.get("name"), "name label should be set and non-empty"


def test_version_label(container):
    """Verify version label is set."""
    labels = container.get_labels()
    assert labels.get("version"), "version label should be set and non-empty"


def test_k8s_display_name_label(container):
    """Verify Kubernetes display name label is set."""
    labels = container.get_labels()
    assert labels.get("io.k8s.display-name"), "Kubernetes display name label should be set"


def test_opencontainers_source_label(container):
    """Verify OCI source label points to GitHub."""
    labels = container.get_labels()
    source = labels.get("org.opencontainers.image.source", "")
    assert source, "OCI source label should be set"
    assert "github.com" in source, f"OCI source should point to GitHub, got: {source}"


# --- Security Tests ---


def test_shadow_not_readable(container):
    """Verify /etc/shadow is not readable by container user."""
    result = container.run("cat /etc/shadow")
    assert result.returncode != 0
