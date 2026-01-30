# AGENTS.md - AI Agent Instructions for ODH Base Containers

## Project Overview

This repository provides standardized Containerfiles for building Open Data Hub (ODH) midstream base images for AI/ML workloads in OpenShift AI.

| Image  | Base OS          | Versions               |
|--------|------------------|------------------------|
| Python | UBI 9            | 3.12                   |
| CUDA   | CentOS Stream 9  | 12.8, 12.9, 13.0, 13.1 |

## Repository Structure

```text
base-containers/
├── cuda/                                 # CUDA version directories
│   ├── 12.8/
│   │   ├── Containerfile                 # CUDA 12.8 Containerfile
│   │   └── app.conf                      # CUDA 12.8 build arguments
│   ├── 12.9/
│   │   ├── Containerfile
│   │   └── app.conf
│   ├── 13.0/
│   │   ├── Containerfile
│   │   └── app.conf
│   └── 13.1/
│       ├── Containerfile
│       └── app.conf
├── python/                               # Python version directories
│   └── 3.12/
│       ├── Containerfile                 # Python 3.12 Containerfile
│       └── app.conf                      # Python 3.12 build arguments
├── Containerfile.cuda.template           # Template for new CUDA versions
├── Containerfile.python.template         # Template for new Python versions
├── .hadolint.yaml                        # Hadolint linter configuration
├── requirements-build.txt                # Build-time deps (uv) - Dependabot updates
├── scripts/
│   ├── build.sh                          # Main build script
│   ├── generate-containerfile.sh         # Generate Containerfile from template
│   ├── lint-containerfile.sh             # Containerfile linter (Hadolint)
│   └── fix-permissions                   # OpenShift permission fixer
├── .github/
│   └── workflows/
│       └── ci.yml                        # CI workflow (Hadolint, tests)
└── docs/
    └── RATIONALE.md
```

## Build Commands

```bash
# Build specific versions
./scripts/build.sh cuda-12.8              # Build CUDA 12.8 image
./scripts/build.sh cuda-12.9              # Build CUDA 12.9 image
./scripts/build.sh cuda-13.0              # Build CUDA 13.0 image
./scripts/build.sh cuda-13.1              # Build CUDA 13.1 image
./scripts/build.sh python-3.12            # Build Python 3.12 image

# Build all versions of a type
./scripts/build.sh cuda                   # Build all CUDA versions
./scripts/build.sh python                 # Build all Python versions

# Build everything
./scripts/build.sh all                    # Build all images
```

## Lint Commands

```bash
./scripts/lint-containerfile.sh                         # Lint all Containerfiles
./scripts/lint-containerfile.sh cuda/12.8/Containerfile # Lint specific file
./scripts/lint-containerfile.sh cuda/*/Containerfile    # Lint matching files
```

Hadolint configuration is in `.hadolint.yaml`. Run linting before submitting PRs.

## Adding New Versions

### Adding a New CUDA Version

1. Generate the Containerfile from template:
   ```bash
   ./scripts/generate-containerfile.sh cuda 13.2
   ```

2. Create the app.conf with version-specific values (use an existing version as reference):
   - Get version numbers from [NVIDIA CUDA Dockerfiles](https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist)
   - Create `cuda/13.2/app.conf`

3. Build and test:
   ```bash
   ./scripts/build.sh cuda-13.2
   ```

### Adding a New Python Version

1. Generate the Containerfile from template:
   ```bash
   ./scripts/generate-containerfile.sh python 3.13
   ```

2. Create the app.conf with version-specific values:
   - Update BASE_IMAGE to the appropriate UBI Python image
   - Create `python/3.13/app.conf`

3. Build and test:
   ```bash
   ./scripts/build.sh python-3.13
   ```

## Build System

Config files in `<type>/<version>/app.conf` are passed directly to podman via `--build-arg-file`. Format: `KEY=value` (one per line, `#` comments allowed). DO NOT source these as shell scripts or use shell syntax.

## Code Style Guidelines

### Containerfiles
- Use section headers with `# ----` separators
- Group related ENV statements
- Use `--chmod` and `--chown` in COPY commands
- Pin package versions via build args, not hardcoded
- Edit templates (`Containerfile.*.template`), then regenerate version-specific files

### Template Placeholders
- CUDA templates use: `{{CUDA_MAJOR_MINOR}}` (12-8), `{{CUDA_MAJOR_MINOR_DOT}}` (12.8), `{{CUDA_MAJOR}}` (12)
- Python templates use: `{{PYTHON_VERSION}}` (3.12), `{{PYTHON_VERSION_NODOT}}` (312)

### Config Files (app.conf)
- Format: `KEY=value` (no `export`, no `$(...)`)
- Include source URLs for version numbers

## Container Standards

| Property | Value |
|----------|-------|
| User ID | 1001 |
| Group ID | 0 (root group for OpenShift) |
| Workdir | `/opt/app-root/src` |
| OpenShift SCC | `restricted` compatible |

## Common Patterns

**Adding a build argument:** Add to `<type>/<version>/app.conf`, then add corresponding `ARG` in the Containerfile template.

**Updating versions:** Edit the appropriate `app.conf` file and run `./scripts/build.sh <type>-<version>` to test.

**Updating all versions:** When changing template files, regenerate all version-specific Containerfiles.

## Things to Avoid

- DO NOT hardcode versions in Containerfiles - use build args
- DO NOT use `:latest` tags in production builds
- DO NOT run containers as root (UID 0) in final image
- DO NOT edit version-specific Containerfiles directly - edit templates instead

## External Resources

- [NVIDIA CUDA Dockerfiles](https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist)
- [UBI Python Images](https://catalog.redhat.com/software/containers/ubi9/python-312)
- [uv Package Manager](https://github.com/astral-sh/uv/releases)
- [buildah-build(1) documentation](https://github.com/containers/buildah/blob/main/docs/buildah-build.1.md)
- [Hadolint - Dockerfile Linter](https://github.com/hadolint/hadolint)
