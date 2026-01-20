"""Common tests that apply to both Python and CUDA images.

These tests verify core functionality that should work identically
across all ODH base container images.
"""

import pytest

# Common paths used across tests (mirrors conftest.py)
APP_ROOT = "/opt/app-root"
WORKDIR = f"{APP_ROOT}/src"


@pytest.fixture(params=["python_container", "cuda_container"])
def container(request):
    """Parameterize to run same tests against both images."""
    return request.getfixturevalue(request.param)


# --- Smoke Tests ---


def test_python_version(container):
    """Verify Python 3.12 is installed and working."""
    result = container.run("python --version")
    assert result.returncode == 0
    assert "Python 3.12" in result.stdout


def test_pip_available(container):
    """Verify pip is installed and working."""
    result = container.run("pip --version")
    assert result.returncode == 0


def test_uv_available(container):
    """Verify uv package manager is installed and working."""
    result = container.run("uv --version")
    assert result.returncode == 0


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


# --- Configuration Tests ---


def test_pip_conf_exists(container):
    """Verify pip configuration file exists."""
    assert container.file_exists("/etc/pip.conf"), "pip configuration file not found"


def test_pip_conf_valid(container):
    """Verify pip configuration contains global section."""
    result = container.run("cat /etc/pip.conf")
    assert "[global]" in result.stdout, "pip.conf missing [global] section"


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


# --- Security Tests ---


def test_shadow_not_readable(container):
    """Verify /etc/shadow is not readable by container user."""
    result = container.run("cat /etc/shadow")
    assert result.returncode != 0
