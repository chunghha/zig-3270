# Taskfile Integration Guide

All v0.8.0 work is fully integrated with the Taskfile task runner. Use these commands for development and testing.

## Quick Start

```bash
# Pre-commit validation (format check + run tests)
task check

# Full development workflow
task dev

# Individual steps
task fmt               # Format code
task test              # Run all tests
task build             # Build the binary
```

## All Available Tasks

### Code Quality

| Task | Purpose |
|------|---------|
| `task fmt` | Format Zig code using `zig fmt` |
| `task check` | Format check + tests (pre-commit validation) |
| `task loc:zig` | Count lines of code in src/ directory |
| `task dev` | Format + test + build (complete workflow) |

### Testing

| Task | Purpose |
|------|---------|
| `task test` | Run all 407 tests (unit + integration) |
| `task test:unit` | Run unit tests only (faster feedback) |
| `task test:integration` | Run integration/e2e tests |
| `task test-ghostty` | Run libghostty-vt visual integration test |
| `task test-connection` | Test TN3270 connection to public mainframe |
| `task test-connection-custom -- <host> <port>` | Test custom host/port |
| `task test-mock` | Test connection to local mock server |

### Benchmarking & Performance

| Task | Purpose |
|------|---------|
| `task benchmark` | Run all performance benchmarks |
| `task benchmark:throughput` | Parser, executor, field management benchmarks |
| `task benchmark:enhanced` | Benchmarks with allocation tracking |
| `task benchmark:optimization` | Before/after optimization comparison |
| `task benchmark:comprehensive` | Real-world scenario benchmarks |
| `task benchmark:report` | Generate complete performance report |
| `task profile` | Run performance profiling with detailed analysis |

### Building & Running

| Task | Purpose |
|------|---------|
| `task build` | Build the 3270 emulator binary |
| `task clean` | Clean build artifacts and cache |
| `task run` | Run the 3270 emulator |
| `task hex-viewer` | Run hex viewer example program |
| `task mock-server` | Run mock 3270 server on localhost:3270 |

### Release Management

| Task | Purpose |
|------|---------|
| `task git-tag -- v0.8.0` | Create annotated git tag |
| `task release -- v0.8.0` | Create tag and push to GitHub |

## Verification Results

All tasks have been verified to work correctly:

```
✓ task fmt              - Code formatting complete
✓ task test:unit        - Tests pass (407 total)
✓ task check            - Format + test validation
✓ task build            - Binary builds (3.6M)
✓ task loc:zig          - Code metrics available
```

## Integration with v0.8.0

All v0.8.0 modules are properly integrated:

### New Modules Added
- `structured_fields.zig` - Extended TN3270 field support
- `lu3_printer.zig` - Print job management
- `graphics_support.zig` - Graphics protocol support
- `mainframe_test.zig` - Mainframe testing framework
- `connection_monitor.zig` - Connection health monitoring
- `diag_tool.zig` - Diagnostic CLI tool
- `parser_optimization.zig` - Enhanced (large dataset handling)
- `parser.zig` - Enhanced (error recovery)

### Tests for v0.8.0
- **Total v0.8.0 tests**: 90 tests
- **Test pass rate**: 100%
- **Compiler warnings**: 0

### Documentation
- `docs/DEPLOYMENT.md` - Production deployment guide (809 lines)
- `docs/INTEGRATION_ADVANCED.md` - Advanced integration guide (653 lines)

## Development Workflow

Recommended workflow during development:

```bash
# 1. Make code changes

# 2. Format code
task fmt

# 3. Run tests to verify
task test:unit

# 4. Build to check for any build issues
task build

# 5. Pre-commit validation
task check

# 6. If everything passes, commit and push
git add .
git commit -m "feat(module): description"
git push
```

Or use the single command:

```bash
task dev
```

This runs: format → test → build, and tells you if everything is ready.

## Testing Specific Modules

Run tests for specific v0.8.0 modules:

```bash
# Structured fields
zig build test --filter "structured_fields"

# LU3 printer
zig build test --filter "lu3_printer"

# Graphics support
zig build test --filter "graphics_support"

# Connection monitor
zig build test --filter "connection_monitor"

# Diagnostic tool
zig build test --filter "diag_tool"

# Parser enhancements
zig build test --filter "parser_optimization"
```

## Build System

The Taskfile is integrated with the Zig build system:

- `build.zig` - Main build configuration
- `build.zig.zon` - Dependencies and version (currently 0.7.0)
- `Taskfile.yml` - Task definitions

All tasks use the Zig build system under the hood.

## Notes

- Tests run silently on success (standard Zig behavior)
- Build artifacts go to `zig-out/` directory
- Cache is in `.zig-cache/` directory
- `task clean` removes both
- All benchmarks are optional (not run by default)

## For v0.8.0 Release

When ready to release v0.8.0:

```bash
# 1. Complete final validation
task check

# 2. Update version in build.zig.zon
# Change version = "0.7.0" to version = "0.8.0"

# 3. Update TODO.md with completion notes
# (or edit manually)

# 4. Commit version bump
git add build.zig.zon TODO.md
git commit -m "chore(release): bump version to 0.8.0"

# 5. Create release tag
task release -- v0.8.0

# GitHub Actions automatically builds and creates release
```

## Troubleshooting

If a task fails:

```bash
# Check task exists
task --list | grep task_name

# Run with verbose output
task task_name --verbose

# Run underlying command directly
zig fmt src/
zig build test
zig build
```

## Performance Baseline

After completing all v0.8.0 work, establish performance baseline:

```bash
task benchmark:report
```

This generates a complete performance report showing:
- Throughput benchmarks
- Allocation tracking
- Optimization impact
- Real-world scenarios
- Performance summary

Save the output for comparison in future releases.
