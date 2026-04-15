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
| CUDA   | 12.8, 12.9, 13.0, 13.1, 13.2 | CentOS Stream 9  |
| ROCm   | 6.4                    | CentOS Stream 9  |

## Pulling Base Images

The ODH base images are published to [quay.io/opendatahub](https://quay.io/organization/opendatahub) and ready to use.

### Python Images

| Version | Image | Quay.io Repository |
|---------|-------|-------------------|
| 3.12 | `quay.io/opendatahub/odh-midstream-python-base-3-12` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-python-base-3-12) |

```bash
# Pull Python 3.12 base image
podman pull quay.io/opendatahub/odh-midstream-python-base-3-12
```

### CUDA Images

| Version | Image | Quay.io Repository |
|---------|-------|-------------------|
| 12.8 | `quay.io/opendatahub/odh-midstream-cuda-base-12-8` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-cuda-base-12-8) |
| 12.9 | `quay.io/opendatahub/odh-midstream-cuda-base-12-9` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-cuda-base-12-9) |
| 13.0 | `quay.io/opendatahub/odh-midstream-cuda-base-13-0` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-cuda-base-13-0) |
| 13.1 | `quay.io/opendatahub/odh-midstream-cuda-base-13-1` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-cuda-base-13-1) |
| 13.2 | `quay.io/opendatahub/odh-midstream-cuda-base-13-2` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-cuda-base-13-2) |

```bash
# Pull CUDA 12.8 base image
podman pull quay.io/opendatahub/odh-midstream-cuda-base-12-8

# Pull CUDA 13.2 base image
podman pull quay.io/opendatahub/odh-midstream-cuda-base-13-2
```

### ROCm Images

| Version | Image | Quay.io Repository |
|---------|-------|-------------------|
| 6.4 | `quay.io/opendatahub/odh-midstream-rocm-base-6-4` | [View on Quay.io](https://quay.io/repository/opendatahub/odh-midstream-rocm-base-6-4) |

```bash
# Pull ROCm 6.4 base image (x86_64 only)
podman pull quay.io/opendatahub/odh-midstream-rocm-base-6-4
```

## Repository Structure

Each image type has version-specific directories containing a `Containerfile` and `app.conf`:

```text
cuda/<version>/Containerfile      # CUDA image definition
cuda/<version>/app.conf           # CUDA build arguments
rocm/<version>/Containerfile      # ROCm image definition
rocm/<version>/app.conf           # ROCm build arguments
python/<version>/Containerfile    # Python image definition
python/<version>/app.conf         # Python build arguments
```

## Quick Start

### Using Build Script (Recommended)

```bash
# Build a specific version
./scripts/build.sh <type>-<version>    # e.g., cuda-12.8, python-3.12

# Build all versions of a type
./scripts/build.sh <type>              # e.g., cuda, rocm, python

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

## Why Different Base Images?

| Template | Base | Reason |
|----------|------|--------|
| Python (CPU) | UBI 9 | Smaller footprint, Red Hat supported |
| CUDA (GPU) | CentOS Stream 9 | CUDA requires OpenGL/mesa libs not in UBI 9 |
| ROCm (GPU) | CentOS Stream 9 | ROCm packages need CentOS Stream 9 / RHEL 9 repos |

**Note:** 
* CUDA packages fail on UBI 9 due to missing dependencies (OpenGL, mesa libs). CentOS Stream 9 includes these libraries.
* ROCm images are x86_64 only — AMD does not provide ARM64 ROCm packages.
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
FROM quay.io/opendatahub/odh-midstream-python-base-3-12

# pip and uv are pre-configured with package indexes
COPY requirements.txt .
RUN pip install -r requirements.txt
# Or use uv (faster): RUN uv pip install -r requirements.txt

COPY --chown=1001:0 . .
CMD ["python", "app.py"]
```

### CUDA Application

```dockerfile
FROM quay.io/opendatahub/odh-midstream-cuda-base-12-8

# pip and uv are pre-configured with PyPI + PyTorch CUDA indexes
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY --chown=1001:0 . .
CMD ["python", "train.py"]
```

### ROCm Application

```dockerfile
FROM quay.io/opendatahub/odh-midstream-rocm-base-6-4

# pip and uv are pre-configured with PyPI + PyTorch ROCm indexes
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY --chown=1001:0 . .
CMD ["python", "train.py"]
```

## Adding New Versions

```bash
./scripts/generate-containerfile.sh <type> <version>   # e.g., cuda 13.2, rocm 6.5, python 3.13
```

See the detailed guides:
- [Adding a Python version](docs/ADDING-PYTHON-VERSION.md)
- [Adding a ROCm version](docs/ADDING-ROCM-VERSION.md)

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
