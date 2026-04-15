# Adding a New ROCm Version

> **Note:** ROCm images are x86_64 only -- AMD does not provide ARM64 ROCm packages.

## Quick Start

```bash
# 1. Create the version directory, Containerfile, and starter app.conf
./scripts/generate-containerfile.sh rocm 6.5

# 2. Update rocm/6.5/app.conf (pin BASE_IMAGE digest, set ROCm version numbers)

# 3. Build, lint, and test
./scripts/build.sh rocm-6.5
./scripts/lint-containerfile.sh rocm/6.5/Containerfile
```

## Step-by-Step

### 1. Generate the version directory

```bash
./scripts/generate-containerfile.sh rocm 6.5
```

This creates:
- `rocm/6.5/Containerfile` (from the template)
- `rocm/6.5/app.conf` (copied from the latest existing version with version strings updated)

### 2. Update `rocm/6.5/app.conf`

The generate script auto-updates version strings (`ROCM_MAJOR`, `ROCM_MAJOR_MINOR`, `ROCM_MAJOR_MINOR_DOT`, `PIP_EXTRA_INDEX_URL`, `UV_TORCH_BACKEND`). You still need to:

- **Pin the `BASE_IMAGE` digest** -- look up from [quay.io/sclorg/python-312-c9s](https://quay.io/repository/sclorg/python-312-c9s), or let Renovate auto-pin it
- **Set `ROCM_VERSION`** to the full patch version (e.g., `6.5.0`) -- find it at [repo.radeon.com/rocm/el9/](https://repo.radeon.com/rocm/el9/)
- **Verify** `PIP_EXTRA_INDEX_URL` and `UV_TORCH_BACKEND` match the new version

### 3. Build, lint, and test

```bash
./scripts/build.sh rocm-6.5
```

Lint the generated Containerfile:
```bash
./scripts/lint-containerfile.sh rocm/6.5/Containerfile
```

Run the image tests (the image tag comes from `IMAGE_TAG` in `app.conf`):
```bash
ROCM_IMAGE=localhost/odh-midstream-rocm-base:6.5-py312 \
ROCM_VERSION=6.5 \
  pytest tests/test_rocm_image.py tests/test_common.py -v
```

### 4. Add Tekton pipelines

Create Konflux pipeline definitions for the new version:
- `.tekton/odh-midstream-rocm-base-<major>-<minor>-pull-request.yaml`
- `.tekton/odh-midstream-rocm-base-<major>-<minor>-push.yaml`

Copy from an existing ROCm version's pipeline files and update version references.

### 5. Review and submit

```bash
git diff
# Review changes, then open a PR
```

If the script fails partway through, revert with `git checkout -- .` and re-run.
