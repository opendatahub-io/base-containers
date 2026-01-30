# Development Guide

This guide covers how to set up a development environment, run tests, and use the code quality tools for the ODH Base Containers project.

## Prerequisites

- Python 3.12+
- Podman (for building and testing container images)
- Git

## Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/opendatahub-io/base-containers.git
   cd base-containers
   ```

2. Create a virtual environment and install dependencies:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -e ".[dev]"
   ```

   This installs all development dependencies (pytest, ruff, mypy, tox) defined in `pyproject.toml`.

## Code Quality

We use [ruff](https://docs.astral.sh/ruff/) for linting/formatting and [mypy](https://mypy.readthedocs.io/) for type checking. These are configured in `pyproject.toml`.

### Using tox (Recommended)

[tox](https://tox.wiki/) provides isolated environments for running checks:

```bash
# Run all checks (lint + type)
tox

# Run only linting (ruff check + format check)
tox -e lint

# Run only type checking (mypy)
tox -e type

# Auto-format code
tox -e format
```

### Running Directly

You can also run the tools directly:

```bash
# Lint check
ruff check tests/

# Format check
ruff format --check tests/

# Auto-format
ruff format tests/

# Type check
mypy tests/
```

## Containerfile Linting (Hadolint)

Use the lint script to check Containerfiles. If Hadolint is not installed locally,
the script falls back to running Hadolint via podman.

```bash
# Lint all Containerfiles in project
./scripts/lint-containerfile.sh

# Lint specific file
./scripts/lint-containerfile.sh Containerfile.python
./scripts/lint-containerfile.sh path/to/Dockerfile
```

## Building Images

Use the build script to build container images:

```bash
# Build Python image
./scripts/build.sh python

# Build CUDA image
./scripts/build.sh cuda

# Build all images
./scripts/build.sh all
```

## Running Tests

Tests require the container images to be built first and their names passed via environment variables.

### Using tox

```bash
PYTHON_IMAGE=quay.io/opendatahub/odh-midstream-python-base:3.12-ubi9 \
CUDA_IMAGE=quay.io/opendatahub/odh-midstream-cuda-base:12.8-py312 \
tox -e test
```

### Running Directly

```bash
# Run all tests
PYTHON_IMAGE=<image:tag> CUDA_IMAGE=<image:tag> pytest tests/ -v

# Run only Python image tests
PYTHON_IMAGE=<image:tag> pytest tests/test_python_image.py tests/test_common.py -v

# Run only CUDA image tests
CUDA_IMAGE=<image:tag> pytest tests/test_cuda_image.py tests/test_common.py -v
```

### Test Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PYTHON_IMAGE` | Python base image to test | `quay.io/opendatahub/odh-midstream-python-base:3.12-ubi9` |
| `CUDA_IMAGE` | CUDA base image to test | `quay.io/opendatahub/odh-midstream-cuda-base:12.8-py312` |
| `PYTHON_VERSION` | Expected Python version for validation | `3.12` |
| `CUDA_VERSION` | Expected CUDA version for validation | `12.8`, `12.9`, `13.0`, `13.1` |

If `PYTHON_IMAGE` or `CUDA_IMAGE` is not set, the corresponding tests will be skipped.
If `PYTHON_VERSION` or `CUDA_VERSION` is not set, version validation tests will be skipped with a message.

**Note:** Always set the version environment variable to match the image being tested. For example, to test CUDA 13.0:

```bash
CUDA_IMAGE=localhost/odh-midstream-cuda-base:13.0-py312 \
CUDA_VERSION=13.0 \
pytest tests/test_cuda_image.py tests/test_common.py -v
```


## CI Workflow

GitHub Actions automatically runs on every PR and push to `main`:

| Job | Trigger | Description |
|-----|---------|-------------|
| `lint` | PR, push | Runs `ruff check` and `ruff format --check` |
| `type-check` | PR, push | Runs `mypy` type checking |
| `lint-containerfiles` | PR, push | Lints changed Containerfiles with Hadolint |
| `test-python-image` | PR, push | Builds Python image and runs tests when Python-related files change |
| `test-cuda-image` | PR, push | Builds CUDA image and runs tests when CUDA-related files change |
| `ci-status` | PR, push | Aggregates required jobs for branch protection |

The `ci-status` job always runs and fails if any required job fails or is cancelled.
Conditional jobs (like `lint-containerfiles` and `test-cuda-image`) may be skipped
when changes do not apply.

### Before Submitting a PR

Ensure your changes pass locally:

```bash
tox                    # Run lint + type checks
tox -e test            # Run tests (if images are built)
```

