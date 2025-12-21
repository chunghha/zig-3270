# Release Notes Template

## v0.2.0 - Quality Assurance & Performance

### New Features
- EBCDIC encoder/decoder for IBM mainframe character encoding
- Structured error handling with context and recovery suggestions
- Configurable debug logging system with per-module filtering
- Memory and timing profiler for performance analysis

### Improvements
- Reduced emulator.zig coupling (12→4 imports, 67% reduction)
- Consolidated parsing utilities for DRY code
- Added 12 comprehensive end-to-end integration tests
- Comprehensive PERFORMANCE.md guide with optimization roadmap

### Quality
- 121+ tests with 100% pass rate
- Full EBCDIC character set support (16 tests)
- Error context types with recovery suggestions (9 tests)
- Debug logging with 5 severity levels (11 tests)
- Memory profiler with reporting (11 tests)

### Documentation
- QUICKSTART.md - Quick reference and development workflow
- docs/PERFORMANCE.md - Performance profiling and optimization guide
- Updated TODO.md with all 5 priorities complete

### Code Metrics
- 4,074 lines of code
- 33 modules
- 100% test pass rate
- Conventional commit messages

## v0.1.0 - Foundation

### Initial Release
- TN3270 terminal emulator in Zig
- 24×80 character screen buffer
- Field management and keyboard input
- Protocol parsing and command execution
- Hex viewer utility
- 60+ unit tests

---

## Versioning Strategy

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR** (v1.0.0): Breaking changes to API or protocol
- **MINOR** (v0.2.0): New features, backward compatible
- **PATCH** (v0.2.1): Bug fixes only

### Creating a Release

```bash
# Create version tag
git tag -a v0.2.0 -m "Release v0.2.0 - Quality Assurance & Performance"

# Push tag to trigger CI/release
git push origin v0.2.0
```

GitHub Actions will:
1. Run tests and build on all platforms
2. Create a GitHub Release
3. Attach binaries as release assets
4. Generate release notes from commits

### Release Assets

Each release includes:
- Compiled binaries for Linux and macOS
- Documentation (README, QUICKSTART, guides)
- Source code as zip/tarball

### Pre-Release Checklist

Before creating a release tag:

```bash
# Verify all tests pass
task check

# Update version in code if needed
# (Currently uses git tags for versioning)

# Update TODO.md with completed work
# Update relevant documentation

# Create and push tag
git tag -a v0.2.0 -m "Release message"
git push origin v0.2.0
```
