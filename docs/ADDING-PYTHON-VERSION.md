# Adding a New Python Version

## Quick Start

```bash
# 1. Create the version directory, Containerfile, and starter app.conf
./scripts/generate-containerfile.sh python 3.13

# 2. Review and update python/3.13/app.conf (pin BASE_IMAGE digest, verify values)

# 3. Build, lint, and test
./scripts/build.sh python-3.13
./scripts/lint-containerfile.sh python/3.13/Containerfile

# 4. (Optional) Make it the project default
./scripts/update-default-python-version.sh 3.13           # preview changes
./scripts/update-default-python-version.sh 3.13 --apply   # apply changes
```

## Step-by-Step

### 1. Generate the version directory

```bash
./scripts/generate-containerfile.sh python 3.13
```

This creates:
- `python/3.13/Containerfile` (from the template)
- `python/3.13/app.conf` (copied from the latest existing version with version strings updated)

### 2. Review `python/3.13/app.conf`

The generated `app.conf` has version strings updated automatically, but you should:
- **Pin the BASE_IMAGE digest** -- look up the digest from the [Red Hat container catalog](https://catalog.redhat.com/software/containers/search), or let Renovate auto-pin it on its next run
- Verify all version strings are correct

### 3. Build, lint, and test

```bash
./scripts/build.sh python-3.13
```

Lint the generated Containerfile:
```bash
./scripts/lint-containerfile.sh python/3.13/Containerfile
```

Run the image tests (the image tag comes from `IMAGE_TAG` in `app.conf`):
```bash
PYTHON_IMAGE=quay.io/opendatahub/odh-midstream-python-base:py313 \
  pytest tests/test_python_image.py tests/test_common.py -v
```

### 4. (Optional) Update the project default

If this version should become the new default across CI and tooling:

```bash
./scripts/update-default-python-version.sh 3.13           # preview
./scripts/update-default-python-version.sh 3.13 --apply   # apply
```

This updates:
- `.github/workflows/ci.yml` (python-version defaults)
- `pyproject.toml` (target-version, python_version)
- `tox.ini` (basepython)
- `renovate.json` (description, allowedVersions)

The current default version is auto-detected from `pyproject.toml`.

### 5. Review and submit

```bash
git diff
# Review changes, then open a PR
```

If the script fails partway through, revert with `git checkout -- .` and re-run.
