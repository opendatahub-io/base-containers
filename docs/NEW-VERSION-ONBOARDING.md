# Konflux Pipeline Onboarding Guide

This document describes the complete process for onboarding new CUDA or Python versions to Konflux pipelines for production builds.

---

## TL;DR - Recommended Order of Operations

> **Important**: The order matters! If you push Containerfiles before the pipeline exists, you'll need to push additional changes to trigger the pipeline after it's created.

| Step | What | Where | Why This Order |
|------|------|-------|----------------|
| 1 | Create Quay image repository | `app-interface` repo | Needed before Konflux can push images |
| 2 | Register Konflux component | `konflux-release-data` repo | Creates the pipeline PR in base-containers |
| 3 | Wait for pipeline PR | GitHub (auto-created) | Konflux generates boilerplate pipelines |
| 4 | Customize pipelines + Add Containerfiles | `base-containers` GitHub | Single PR with everything, triggers on merge |

**Optimal approach**: Prepare your Containerfiles locally, but don't push until the pipeline PR arrives. Then combine them into a single PR.

---

## Step 1: Create Quay Image Repository (If Needed)

Before Konflux can push images, the Quay image repository must exist with proper permissions.

### 1.1 Check if Image Repository Exists

Check if an image repository already exists at:
```text
quay.io/opendatahub/odh-midstream-{type}-base-{version}
```

Example: `quay.io/opendatahub/odh-midstream-cuda-base-13-2`

### 1.2 Request New Image Repository via app-interface

If the image repository doesn't exist, create an MR in the `app-interface` repo.

The MR should:
- Add the new image repository to the Quay organization configuration
- Grant the Konflux service account push permissions


### 1.3 Quay Organization Details

| Property | Value |
|----------|-------|
| Quay Organization | `opendatahub` |
| Konflux Tenant | `open-data-hub-tenant` |

---

## Step 2: Register Component in konflux-release-data

Once the Quay image repository exists (or is being created), register the component in Konflux.

### 2.1 Clone the Repository

Clone the `konflux-release-data` repository (internal GitLab).

### 2.2 Locate the ODH Tenant Configuration

The configuration file is at:
```text
tenants-config/cluster/stone-prd-rh01/tenants/open-data-hub-tenant/odh-base-containers.yaml
```

### 2.3 Add New Component

Add a new component entry following this naming convention:

| Type   | Component Name |
|--------|----------------|
| CUDA   | `odh-midstream-cuda-base-<major-version>-<minor-version>` |
| Python | `odh-midstream-python-base-<major-version>-<minor-version>` |

Example component configuration (refer to existing components in the file):

```yaml
# Add under components section
- name: odh-midstream-cuda-base-13-2
  containerImage: quay.io/opendatahub/odh-midstream-cuda-base-13-2
  # ... other configuration following existing patterns
```

### 2.4 Submit the MR

The MR requires approval from CODEOWNERS.
---

## Step 3: Wait for Konflux Pipeline PR

After the konflux-release-data MR is merged, Konflux **automatically creates a PR** to this repository with boilerplate Tekton pipelines.

### 3.1 What Konflux Creates

Konflux creates two pipeline files per component in `.tekton/`:

| File | Purpose |
|------|---------|
| `odh-midstream-{type}-base-{version}-pull-request.yaml` | PR validation builds |
| `odh-midstream-{type}-base-{version}-push.yaml` | Main branch builds (pushes to Quay) |

---

## Step 4: Customize Pipelines and Add Containerfiles

This is where you combine the pipeline customizations with your Containerfile changes.

### 4.1 Prepare Containerfiles Locally

While waiting for the pipeline PR, prepare your Containerfiles. Refer to [DEVELOPMENT.md](DEVELOPMENT.md).

### 4.2 Required Pipeline Customizations

When the Konflux PR arrives, you need to customize the generated pipelines:

#### A. Update CEL Expression (Critical)

By default, Konflux pipelines trigger on **all** changes. You **must** restrict triggers to only relevant paths.

In both `-pull-request.yaml` and `-push.yaml` files, update the `on-cel-expression`:

**For CUDA 13.2 (push.yaml):**
```yaml
pipelinesascode.tekton.dev/on-cel-expression: |
  event == "push" && target_branch == "main" && (
    'cuda/13.2/**'.pathChanged() ||
    'requirements-build.txt'.pathChanged() ||
    'scripts/fix-permissions'.pathChanged() ||
    '.tekton/odh-midstream-cuda-base-13-2-push.yaml'.pathChanged()
  )
```

**For CUDA 13.2 (pull-request.yaml):**
```yaml
pipelinesascode.tekton.dev/on-cel-expression: |
  event == "pull_request" && (
    'cuda/13.2/**'.pathChanged() ||
    'requirements-build.txt'.pathChanged() ||
    'scripts/fix-permissions'.pathChanged() ||
    '.tekton/odh-midstream-cuda-base-13-2-pull-request.yaml'.pathChanged()
  )
```

#### B. Update Pipeline Parameters

Ensure these parameters point to the correct paths:

```yaml
spec:
  params:
  - name: dockerfile
    value: cuda/13.2/Containerfile    # or python/3.13/Containerfile
  - name: build-args-file
    value: cuda/13.2/app.conf          # or python/3.13/app.conf
  - name: output-image
    value: quay.io/opendatahub/odh-midstream-cuda-base-13-2:{{revision}}
```

### 4.3 Combine Into Single PR (Recommended)

**Best practice**: Add your Containerfiles to the same PR that contains the pipeline customizations.

### 4.4 Alternative: Separate PRs

If you must use separate PRs:

1. **First**: Merge the pipeline PR (with customizations)
2. **Then**: Create a new PR with Containerfiles
3. **Important**: The second PR will trigger the pipeline

> ⚠️ **Warning**: If you merge Containerfiles before pipelines exist, you'll need to push another change to trigger the build.

### 4.5 Reference Pipeline Files

Use existing pipelines as templates:

| Type   | Reference File |
|--------|----------------|
| CUDA   | `.tekton/odh-midstream-cuda-base-13-1-push.yaml` |
| Python | `.tekton/odh-midstream-python-base-3-12-push.yaml` |

---

## Step 5: Verify the Pipeline

After merging:

1. **Check Konflux UI**: Access the Konflux tenant UI for `open-data-hub-tenant`
2. **Verify pipeline triggered**: Look for your component's pipeline run
3. **Check Quay.io**: Verify image was pushed to `quay.io/opendatahub/odh-midstream-{type}-base-{version}`

### Verification Checklist

- [ ] Pipeline runs successfully on push to main
- [ ] Pipeline runs on PR (pull-request pipeline)
- [ ] Image appears in Quay.io with correct tag
- [ ] Pipeline only triggers on relevant path changes (not all PRs)

---

## Component Naming Convention

```text
odh-midstream-{type}-base-{version}
```

| Type   | Version | Full Component Name | Quay Image |
|--------|---------|---------------------|------------|
| cuda   | 12.8    | odh-midstream-cuda-base-12-8 | quay.io/opendatahub/odh-midstream-cuda-base-12-8 |
| cuda   | 12.9    | odh-midstream-cuda-base-12-9 | quay.io/opendatahub/odh-midstream-cuda-base-12-9 |
| cuda   | 13.0    | odh-midstream-cuda-base-13-0 | quay.io/opendatahub/odh-midstream-cuda-base-13-0 |
| cuda   | 13.1    | odh-midstream-cuda-base-13-1 | quay.io/opendatahub/odh-midstream-cuda-base-13-1 |
| python | 3.12    | odh-midstream-python-base-3-12 | quay.io/opendatahub/odh-midstream-python-base-3-12 |

---

## Documentation

- [Konflux Documentation](https://konflux-ci.dev/)
- [Tekton Pipelines Documentation](https://tekton.dev/docs/pipelines/)
