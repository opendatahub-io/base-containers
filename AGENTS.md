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
│   ├── generate-containerfile.sh         # Generate Containerfile + app.conf from template
│   ├── update-default-python-version.sh  # Update default Python version in CI/tooling
│   ├── lint-containerfile.sh             # Containerfile linter (Hadolint)
│   └── fix-permissions                   # OpenShift permission fixer
├── .github/
│   └── workflows/
│       ├── ci.yml                        # CI workflow (Hadolint, tests)
│       └── check-cuda-versions.yml       # Auto-detect new CUDA versions
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

1. Generate the Containerfile and starter app.conf from template:
   ```bash
   ./scripts/generate-containerfile.sh cuda 13.2
   ```

2. Update NVIDIA-specific versions in `cuda/13.2/app.conf` (lines marked with `# TODO`):
   - Get version numbers from [NVIDIA CUDA Dockerfiles](https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist)
   - Pin the BASE_IMAGE digest

3. Build and test:
   ```bash
   ./scripts/build.sh cuda-13.2
   ```

### Adding a New Python Version

1. Generate the Containerfile and starter app.conf from template:
   ```bash
   ./scripts/generate-containerfile.sh python 3.13
   ```

2. Review `python/3.13/app.conf` (version strings are updated automatically):
   - Pin the BASE_IMAGE digest
   - Verify all values are correct

3. Build and test:
   ```bash
   ./scripts/build.sh python-3.13
   ```

4. (Optional) Make it the project default across CI and tooling:
   ```bash
   ./scripts/update-default-python-version.sh 3.13 --apply
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

### Template Build Args
- CUDA templates use build args from `cuda/<version>/app.conf`:
  `CUDA_MAJOR` (12), `CUDA_MAJOR_MINOR` (12-8), `CUDA_MAJOR_MINOR_DOT` (12.8)
- Python templates use build args from `python/<version>/app.conf`:
  `PYTHON_VERSION` (3.12), `PYTHON_VERSION_NODOT` (312)

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

## Automated Version Detection

The repository includes a GitHub Actions workflow that automatically detects new CUDA versions from NVIDIA's container images repository.

### How It Works

The `check-cuda-versions.yml` workflow:
1. **Runs weekly** (Monday 9:00 AM UTC) and on manual trigger
2. **Fetches versions** from [NVIDIA's GitLab repository](https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist)
3. **Compares** with local `cuda/*/` directories
4. **Creates issues** for missing versions (≥ 12.8) with instructions for adding support
5. **Skips duplicates** if an issue already exists for a version

### Manual Trigger

To manually check for new versions:
1. Go to **Actions** → **Check CUDA Versions**
2. Click **Run workflow**
3. Optionally enable **Dry run** to preview without creating issues

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
