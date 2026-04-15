# Why ODH Midstream Base Images?

This document explains the motivation behind creating standardized base container images for Open Data Hub (ODH). It is intended for ODH maintainers, contributors, and downstream engineers working on RHOAI productization.

## Objective

### Standardize Midstream Builds

Provide a single set of maintained base images so that midstream ODH repositories share a consistent, tested foundation — one place to manage Python versions, CUDA versions, security updates, and OpenShift compatibility instead of duplicating that work across 40+ repos.

### Long-Term Goal: Smoother Path to Downstream

The downstream product (RHOAI) is built on RHEL. By using CentOS Stream — which tracks ahead of RHEL — as the base OS for midstream images, we bring the midstream environment as close to downstream as possible. The long-term goal is to close the gap between midstream and downstream base images so that:

- Midstream projects that adopt these base images are **easier to productize** in downstream — for example, rebuilding against RHEL-based images with internal wheels requires changing only build args, not Containerfiles
- Transitioning from midstream to downstream base images is a **smooth, low-risk change** rather than a disruptive migration
- New features and capabilities proven in midstream can be **brought to downstream quickly**, since the underlying base images are already aligned

The goal is met when a midstream consumer can switch to downstream base images by changing only build args (see [Build Arg Swapping](#build-arg-swapping)).

## The Problem

Open Data Hub consists of multiple repositories, each building their own container images. Analysis of 40+ ODH repositories revealed:

| Issue | Impact |
|-------|--------|
| **Fragmented base images** | 20+ different base images across repositories |
| **Inconsistent Python versions** | Python 3.6 to 3.12 in use (3.6 and 3.8 are EOL) |
| **Duplicated CUDA setup** | Multiple repos install CUDA independently (~80 lines each) |
| **Varying patterns** | Different approaches for users, permissions, labels |

### Base Image Fragmentation

Before standardization:

```text
notebooks/           -> quay.io/sclorg/python-312-c9s + custom CUDA
trainer/             -> nvidia/cuda:12.8.1-devel-ubuntu22.04
model-registry/      -> registry.access.redhat.com/ubi9/python-312
llama-stack/         -> registry.access.redhat.com/ubi9/python-312
feast/               -> registry.access.redhat.com/ubi9/python-311
trustyai/            -> registry.access.redhat.com/ubi9/python-311
...
```

Each repository made independent choices, leading to:
- Inconsistent security posture
- Difficult upgrades (update 40+ repos individually)
- Duplicated effort maintaining CUDA/cuDNN versions
- Varying compatibility with OpenShift

## The Solution

Provide **common base images** that ODH repositories can build upon:

| Base Image | Use Case |
|------------|----------|
| `Containerfile.python` | CPU workloads, web services |
| `Containerfile.cuda` | GPU workloads, model training on NVIDIA hardware (multiple CUDA versions: 12.8, 12.9, 13.0, 13.1, 13.2) |
| `Containerfile.rocm` | GPU workloads, model training on AMD hardware (ROCm 6.4, x86_64 only) |

### Benefits

| Benefit | Description |
|---------|-------------|
| **Reduced duplication** | CUDA setup done once, not in every repo |
| **Faster builds** | Downstream images skip base setup |
| **Consistent versions** | Single source of truth for Python, CUDA, cuDNN |
| **Easier upgrades** | Update base image, rebuild consumers |
| **Security** | Centralized vulnerability management |
| **OpenShift compatibility** | Tested patterns for restricted SCC |

### Before and After

**Before (each repo builds CUDA from scratch):**

```dockerfile
FROM quay.io/sclorg/python-312-c9s:c9s
# 80+ lines of CUDA 12.8 installation
RUN dnf install -y cuda-cudart-12-8 cuda-libraries-12-8 ...
RUN dnf install -y libcudnn9-cuda-12 ...
# Application setup
```

**After (repo consumes published base):**

```dockerfile
FROM quay.io/opendatahub/odh-midstream-cuda-base-12-8
# Application setup only
COPY requirements.txt .
RUN pip install -r requirements.txt
```

## Why Multiple CUDA Versions?

The repository maintains multiple CUDA versions (currently 12.8, 12.9, 13.0, 13.1, and 13.2) rather than a single version. Supporting multiple CUDA versions enables midstream projects within the Open Data Hub organization to adopt newer CUDA releases more easily during midstream cycles. Introducing newer CUDA versions in midstream first also prepares the team for a smoother transition when the same versions are later promoted to downstream products.

This approach lets consumers pick the CUDA version that matches their needs:

| Scenario | Recommended Version |
|----------|-------------------|
| Production stability | Older, well-tested version (e.g. 12.8) |
| New GPU features | Latest available version (e.g. 13.2) |
| Gradual migration | Test with newer version before switching |

## Design Decisions

### Why Two Base OS?

| Image | Base OS | Reason |
|-------|---------|--------|
| Python | UBI 9 | Smaller footprint, Red Hat supported |
| CUDA | CentOS Stream 9 | CUDA requires OpenGL/mesa libs not in UBI 9 |
| ROCm | CentOS Stream 9 | ROCm packages need CentOS Stream 9 / RHEL 9 repos |

CUDA packages fail on UBI 9 due to missing dependencies. CentOS Stream 9 provides the required libraries. See [RHAIENG-1532](https://issues.redhat.com/browse/RHAIENG-1532).

### Why Python 3.12?

- Mature, well-tested version with security support until October 2028
- Most ODH repos already use 3.11 or 3.12
- EOL versions (3.6, 3.8) need migration regardless
- Chosen for stability over newest features (Python 3.13+ available but less battle-tested in production)

### Why These Patterns?

The base images combine best practices from multiple ODH repositories:

| Feature | Source | Rationale |
|---------|--------|-----------|
| OCI labels | model-registry | Standard container metadata |
| UID 1001 | notebooks | Standard for UBI Python, OpenShift compatible |
| Group `g=u` | feast, notebooks | Allows arbitrary UID in OpenShift |
| uv package manager | llama-stack | 10-100x faster than pip |
| Pinned digest option | llama-stack | Reproducible builds |

## Alignment with RHOAI

The [Objective](#objective) explains _why_ midstream and downstream alignment matters. This section covers the mechanics — how the two streams differ, what must stay separated, and how build arg swapping bridges the gap.

| Environment | Configuration |
|-------------|---------------|
| **ODH (midstream)** | Default PyPI indexes, public base images |
| **RHOAI (downstream)** | Internal indexes, AIPCC base images |

### Why Separate Base Images Exist

Midstream base images are built with **upstream wheels** from public package indexes (PyPI, PyTorch). Downstream product containers (RHOAI) are built with **downstream wheels** from internal package indexes. This separation is intentional — the two sets of wheels are compiled against different system libraries, and the base images they target are not interchangeable.

### Do Not Mix Wheels and Base Images

> **Warning:** Using wheels from one stream with base images from the other will cause build or runtime failures.

| Combination | Why it fails |
|---|---|
| Downstream wheels in midstream builds | (a) Downstream wheels should not be released freely in midstream. (b) They are not supported outside the downstream base images they were built against. |
| Upstream wheels in downstream containers | Upstream wheels may vendor library versions that conflict with system-level dependencies in the downstream base images, causing hard-to-diagnose runtime errors. |

Even CPU-only wheels for accelerator-specific packages can introduce dependency mismatches in the wrong base image. Keep wheel sources strictly separated.

### Build Arg Swapping

The transparency goal is that consumers should be able to swap midstream for downstream by changing **only build args**, with no Containerfile edits. This is a work in progress.

```bash
# ODH build
podman build -t myapp:odh .

# RHOAI build (internal indexes)
podman build -t myapp:rhoai \
  --build-arg PIP_INDEX_URL=https://aipcc.internal/simple \
  --build-arg PIP_EXTRA_INDEX_URL="" \
  --build-arg UV_TORCH_BACKEND= \
  .
```

The following build args are expected to change between streams:

| Build Arg | ODH (midstream) | RHOAI (downstream) |
|---|---|---|
| `BASE_IMAGE` | Public image (CentOS, UBI) | Internal AIPCC image |
| `PIP_INDEX_URL` | `https://pypi.org/simple` | Internal index URL |
| `PIP_EXTRA_INDEX_URL` | PyTorch public index | Empty (disabled) |
| `UV_TORCH_BACKEND` | CUDA backend (e.g., `cu128`) | Empty (omitted from uv.toml) |

