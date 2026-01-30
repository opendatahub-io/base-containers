# ODH Base Containers

Common base container images for Open Data Hub (ODH) workloads.

## Overview

This repository provides standardized Containerfiles for building ODH midstream base images. These images serve as the foundation for AI/ML workloads in OpenShift AI.

**Why base images?** See [docs/RATIONALE.md](docs/RATIONALE.md) for the motivation behind this project.
For development setup and workflow, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Available Images

| Type   | Versions               | Base OS          |
|--------|------------------------|------------------|
| Python | 3.12                   | UBI 9            |
| CUDA   | 12.8, 12.9, 13.0, 13.1 | CentOS Stream 9  |

## Repository Structure

Each image type has version-specific directories containing a `Containerfile` and `app.conf`:

```text
cuda/<version>/Containerfile      # CUDA image definition
cuda/<version>/app.conf           # CUDA build arguments
python/<version>/Containerfile    # Python image definition
python/<version>/app.conf         # Python build arguments
```

## Quick Start

### Using Build Script (Recommended)

```bash
# Build a specific version
./scripts/build.sh <type>-<version>    # e.g., cuda-12.8, python-3.12

# Build all versions of a type
./scripts/build.sh <type>              # e.g., cuda, python

# Build everything
./scripts/build.sh all

# Show available versions and help
./scripts/build.sh --help
```

### Manual Build

```bash
# Generic pattern
podman build -t <image-name>:<tag> \
  --build-arg-file <type>/<version>/app.conf \
  -f <type>/<version>/Containerfile .

# Example: Build CUDA 12.8
podman build -t odh-midstream-cuda-base:12.8-py312 \
  --build-arg-file cuda/12.8/app.conf \
  -f cuda/12.8/Containerfile .
```

## Why Two Base Images?

| Template | Base | Reason |
|----------|------|--------|
| Python (CPU) | UBI 9 | Smaller footprint, Red Hat supported |
| CUDA (GPU) | CentOS Stream 9 | CUDA requires OpenGL/mesa libs not in UBI 9 |

**Note:** 
* CUDA packages fail on UBI 9 due to missing dependencies (OpenGL, mesa libs). CentOS Stream 9 includes these libraries.
* Python images remain on UBI 9 to minimize migration impact. A unified CentOS Stream 9 base for all images may be considered in the future.

## Common Properties

Both images share consistent configuration:

| Property | Value |
|----------|-------|
| User ID | 1001 |
| Group ID | 0 (root group) |
| Workdir | `/opt/app-root/src` |
| OpenShift SCC | `restricted` compatible |

## Extending Base Images

### Python Application

```dockerfile
FROM quay.io/opendatahub/odh-midstream-python-base:py312

# pip and uv are pre-configured with package indexes
COPY requirements.txt .
RUN pip install -r requirements.txt
# Or use uv (faster): RUN uv pip install -r requirements.txt

COPY --chown=1001:0 . .
CMD ["python", "app.py"]
```

### CUDA Application

```dockerfile
FROM quay.io/opendatahub/odh-midstream-cuda-base:12.8-py312

# pip and uv are pre-configured with PyPI + PyTorch CUDA indexes
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY --chown=1001:0 . .
CMD ["python", "train.py"]
```

## Adding New Versions

Use the generation script to create a new version from the template:

```bash
# Generate Containerfile from template
./scripts/generate-containerfile.sh <type> <version>

# Example: Add CUDA 13.2
./scripts/generate-containerfile.sh cuda 13.2
# Then create cuda/13.2/app.conf with version-specific values
# Get versions from: https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist

# Example: Add Python 3.13
./scripts/generate-containerfile.sh python 3.13
# Then create python/3.13/app.conf with version-specific values
```

After adding a new version, also update `.github/workflows/ci.yml`:
- Add the version to the `matrix.version` array in the corresponding test job
- Add a version-specific path filter if desired (e.g., `cuda-13-2`)

## Build Arguments

Build arguments are defined in `<type>/<version>/app.conf` files. The build script passes these directly via `--build-arg-file`.

To update package versions:

```bash
# Edit the config file
vim <type>/<version>/app.conf

# Rebuild the image
./scripts/build.sh <type>-<version>
```

## CI/CD

Images will be built using [Konflux](https://konflux-ci.dev/) pipelines.

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.
