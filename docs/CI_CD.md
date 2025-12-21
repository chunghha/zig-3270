# CI/CD Pipeline

## Overview

This project uses GitHub Actions for continuous integration and automated releases.

## Workflows

### CI Workflow (`.github/workflows/ci.yml`)

Runs on every push to `main` and pull requests.

**Steps**:
1. **Test** - Format check and unit tests on Ubuntu
2. **Build** - Build release binaries on Ubuntu and macOS
3. **Release** - Create GitHub release on version tags

## Continuous Integration

### On Every Push to `main`

```yaml
- Format check (zig fmt)
- Run all tests (121+ tests)
- Build project (ReleaseSafe)
```

**Status**: Visible on GitHub with green/red check marks

### On Pull Requests

Same checks run before merge - all must pass.

## Creating a Release

### 1. Verify Everything Works Locally

```bash
task check    # Format + test
task build    # Build
task loc      # Check metrics
```

### 2. Update Documentation

- Update `TODO.md` with completed work
- Update relevant files in `docs/`
- Verify `QUICKSTART.md` is current

### 3. Create Version Tag

```bash
# Create annotated tag with message
git tag -a v0.2.0 -m "Release v0.2.0 - Quality Assurance & Performance"

# Push tag (triggers release workflow)
git push origin v0.2.0
```

### 4. GitHub Actions Releases

When you push a version tag (v0.x.x):

1. **Test Job**: Runs full test suite
2. **Build Job**: Builds on Ubuntu and macOS
3. **Release Job**: Creates GitHub Release with:
   - Compiled binaries
   - Documentation
   - Auto-generated release notes

### Release Assets

Each release includes:

```
zig-3270-ubuntu-latest/
  ├── zig-3270           (main executable)
  ├── ghostty-vt-visual-test
  ├── client-test
  ├── mock-server
  └── hex-viewer

zig-3270-macos-latest/
  ├── zig-3270           (main executable)
  ├── ghostty-vt-visual-test
  ├── client-test
  ├── mock-server
  └── hex-viewer

README.md
QUICKSTART.md
docs/
  ├── ARCHITECTURE.md
  ├── PERFORMANCE.md
  ├── HEX_VIEWER.md
  └── ... (all docs)
```

## Version Numbering

Uses [Semantic Versioning](https://semver.org/):

- **v0.1.0** - Foundation (initial release)
- **v0.2.0** - Quality Assurance & Performance
- **v1.0.0** - Production Ready (future)

Format: `v{MAJOR}.{MINOR}.{PATCH}`

## Workflow Files

### `.github/workflows/ci.yml`

Main CI/CD workflow with three jobs:

1. **test** - Verify code quality and tests
2. **build** - Cross-platform binary builds
3. **release** - Create GitHub release (on tags only)

### `.github/workflows/release-notes.md`

Template and guidelines for release notes.

## Monitoring CI

### On GitHub

1. Go to project page
2. Click "Actions" tab
3. See workflow status for each push/PR
4. Click workflow to see detailed logs

### Local Development

Before pushing:

```bash
# Simulate CI environment
task check    # Format check + tests
task build    # Build for release
```

## Troubleshooting

### Build Fails in CI

Check the GitHub Actions logs:
1. Go to Actions tab
2. Click the failing workflow
3. Expand failed job for detailed output

### Release Not Creating

Ensure:
1. Tag follows `v*` pattern (e.g., `v0.2.0`)
2. Tag was pushed to remote: `git push origin v0.2.0`
3. Tests pass (check CI logs)
4. Secrets are configured (typically automatic)

## Setup Instructions

No additional setup needed - CI is ready to use!

When you push a version tag, GitHub Actions automatically:
1. Checks out code
2. Installs Zig
3. Runs tests
4. Builds binaries
5. Creates release with assets

## Environment Variables

Automatically provided by GitHub Actions:

```
GITHUB_TOKEN    - For creating releases
GITHUB_REF      - Current branch/tag
GITHUB_SHA      - Current commit hash
GITHUB_WORKSPACE - Working directory
```

## See Also

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Semantic Versioning](https://semver.org/)
- `QUICKSTART.md` - Local development workflow
- `TODO.md` - Project roadmap
