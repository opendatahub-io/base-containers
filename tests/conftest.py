"""Shared fixtures and helpers for container image testing.

This module provides the ContainerRunner class and pytest fixtures for
testing ODH base container images efficiently using session-scoped containers.

NOTE: All tests using session-scoped containers must be idempotent (read-only).
Do not modify container state as tests may run in any order.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess

import pytest

# Common paths used across tests
APP_ROOT = "/opt/app-root"
WORKDIR = f"{APP_ROOT}/src"


class ContainerRunner:
    """Efficient container runner using session-scoped container with exec.

    Starts a single container per test session and uses 'podman exec' to run
    commands. This avoids the overhead of starting a new container for each test.
    """

    def __init__(self, image: str):
        self.image = image
        self.container_id: str | None = None

    def start(self):
        """Start container in background with sleep infinity."""
        result = subprocess.run(
            ["podman", "run", "-d", "--rm", self.image, "sleep", "infinity"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Failed to start container: {result.stderr}")
        self.container_id = result.stdout.strip()

    def stop(self):
        """Stop and remove container."""
        if self.container_id:
            subprocess.run(
                ["podman", "stop", "-t", "1", self.container_id],
                capture_output=True,
                timeout=30,
                check=False,
            )
            self.container_id = None

    def run(self, command: str, timeout: int = 30) -> subprocess.CompletedProcess:
        """Execute command in running container using podman exec."""
        if not self.container_id:
            raise RuntimeError("Container not started. Call start() first.")
        return subprocess.run(
            ["podman", "exec", self.container_id, "bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def get_env(self, var: str) -> str:
        """Get an environment variable value safely."""
        if not var.replace("_", "").isalnum():
            raise ValueError(f"Invalid environment variable name: {var}")
        result = self.run(f"printenv {var}")
        return result.stdout.strip() if result.returncode == 0 else ""

    def file_exists(self, path: str) -> bool:
        """Check if a file exists."""
        result = self.run(f"test -f {shlex.quote(path)}")
        return result.returncode == 0

    def dir_exists(self, path: str) -> bool:
        """Check if a directory exists."""
        result = self.run(f"test -d {shlex.quote(path)}")
        return result.returncode == 0

    def get_labels(self) -> dict[str, str]:
        """Get image labels using podman inspect.

        Returns an empty dict if labels are null/missing or not a dict,
        ensuring callers can safely use .get() on the result.
        """
        result = subprocess.run(
            ["podman", "inspect", "--format", "{{json .Config.Labels}}", self.image],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if result.returncode == 0:
            try:
                parsed = json.loads(result.stdout)
                # podman can return null (None) if no labels exist
                if isinstance(parsed, dict):
                    return parsed
                return {}
            except json.JSONDecodeError:
                return {}
        return {}

    def get_config(self, key: str) -> str | None:
        """Get image config value using podman inspect."""
        result = subprocess.run(
            ["podman", "inspect", "--format", f"{{{{json .Config.{key}}}}}", self.image],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if result.returncode == 0:
            try:
                value: str | None = json.loads(result.stdout)
                return value
            except json.JSONDecodeError:
                return None
        return None


def _get_required_env(var: str, example: str) -> str:
    """Get a required environment variable or raise with helpful message."""
    value = os.environ.get(var)
    if not value:
        pytest.skip(f"{var} environment variable not set. Example: {var}={example} pytest tests/")
    return value


@pytest.fixture(scope="session")
def python_image():
    """Image name for Python base image.

    Set via PYTHON_IMAGE environment variable.
    Example: PYTHON_IMAGE=quay.io/opendatahub/odh-midstream-python-base:3.12-ubi9
    """
    return _get_required_env(
        "PYTHON_IMAGE",
        "quay.io/opendatahub/odh-midstream-python-base:<tag>",
    )


@pytest.fixture(scope="session")
def cuda_image():
    """Image name for CUDA base image.

    Set via CUDA_IMAGE environment variable.
    Example: CUDA_IMAGE=quay.io/opendatahub/odh-midstream-cuda-base:12.8-py312
    """
    return _get_required_env(
        "CUDA_IMAGE",
        "quay.io/opendatahub/odh-midstream-cuda-base:<tag>",
    )


@pytest.fixture(scope="session")
def python_container(python_image):
    """Session-scoped container runner for Python image.

    Container starts once at session start and stops at session end.
    All tests share the same running container.
    """
    runner = ContainerRunner(python_image)
    runner.start()
    yield runner
    runner.stop()


@pytest.fixture(scope="session")
def cuda_container(cuda_image):
    """Session-scoped container runner for CUDA image.

    Container starts once at session start and stops at session end.
    All tests share the same running container.
    """
    runner = ContainerRunner(cuda_image)
    runner.start()
    yield runner
    runner.stop()
