## What
<!-- Brief description of the change -->


## Why
<!-- Link to issue or motivation -->

Closes #

## Checklist
<!-- Check items that apply. Strike through items that don't apply to this PR: ~[ ]~ -->

### All PRs
- [ ] Linting, formatting, and type checks pass (`tox -e lint`, `tox -e type`)
- [ ] Tests added/updated where applicable (`tox -e test`)

### Containerfile / image changes
- [ ] Edited the `Containerfile.*.template`, not version-specific `<type>/<version>/Containerfile` directly
- [ ] Regenerated version-specific Containerfiles (`./scripts/generate-containerfile.sh`)
- [ ] Containerfile linting passes (`./scripts/lint-containerfile.sh`)
- [ ] Versions and URLs are in `app.conf` build args, not hardcoded
- [ ] Image builds successfully (`./scripts/build.sh <type>-<version>`)
- [ ] No `:latest` tags or root (UID 0) user in container images
