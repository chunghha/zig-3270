# Taskfile Documentation

This folder contains comprehensive documentation for the project's Taskfile.yml task runner.

## Files

### TASKFILE_INTEGRATION.md
Initial Taskfile integration documentation covering:
- Task organization strategy
- Build, test, and benchmark tasks
- Development workflow
- Integration with Zig build system

**When to read**: Understanding the original Taskfile structure and philosophy

### TASKFILE_V0.10_UPDATE.md
Comprehensive documentation of v0.10.x Taskfile updates:
- New test tasks for all v0.10.x priorities (P1, P2, P3, P4)
- New benchmark tasks for v0.10.x validation
- New example program tasks (6 new tasks)
- Updated header comments with quick reference
- All 13 new tasks documented with usage and output examples

**When to read**: Learning about v0.10.x test and example tasks

## Quick Reference

### Running v0.10.x Tests
```bash
task test:v0.10           # All v0.10.x tests (95+)
task test:stability       # v0.10.0: 13 stability tests
task test:regression      # v0.10.0: 12 regression tests
task test:errors          # v0.10.1: 24 error handling tests
task test:hardening       # v0.10.2: 38 hardening tests
```

### Running v0.10.x Performance Validation
```bash
task benchmark:v0.10      # v0.10.x performance validation
```

### Running Example Programs
```bash
task run:batch-processor        # Batch operations (100 items)
task run:batch-processor-large  # Batch operations (1000 items)
task run:session-monitor        # Real-time monitoring
task run:load-test              # Load testing (basic)
task run:load-test-stress       # Load testing (1000 RPS)
task run:audit-analysis         # Audit log analysis
```

### Full Task List
```bash
task --list               # See all available tasks
```

## Available Tasks

See Taskfile.yml in the project root for complete task definitions.

### Code Quality
- `task fmt` - Format code with zig fmt
- `task check` - Format check + tests
- `task dev` - Development workflow (fmt + test + build)
- `task loc` - Count lines of code

### Testing
- `task test` - All tests
- `task test:unit` - Unit tests only
- `task test:integration` - Integration tests
- `task test:v0.10` - All v0.10.x tests (95+)
- `task test:stability` - Stability tests
- `task test:regression` - Regression tests
- `task test:errors` - Error handling tests
- `task test:hardening` - Production hardening tests

### Benchmarking
- `task benchmark` - Full benchmark suite
- `task benchmark:v0.10` - v0.10.x validation
- `task benchmark:throughput` - Throughput benchmarks
- `task benchmark:enhanced` - Enhanced benchmarks
- `task benchmark:optimization` - Optimization benchmarks
- `task benchmark:comprehensive` - Comprehensive benchmarks
- `task benchmark:report` - Performance report
- `task profile` - Performance profiling

### Examples
- `task run:batch-processor` - Batch processing (100 items)
- `task run:batch-processor-large` - Batch processing (1000 items)
- `task run:session-monitor` - Session monitoring
- `task run:load-test` - Load testing
- `task run:load-test-stress` - High-stress load test
- `task run:audit-analysis` - Audit analysis

### Build & Execution
- `task build` - Build the emulator
- `task run` - Run the emulator
- `task clean` - Clean build artifacts

### Integration & Examples
- `task test-ghostty` - libghostty-vt test
- `task test-connection` - Real mainframe test
- `task test-connection-custom` - Custom host test
- `task mock-server` - Mock 3270 server
- `task test-mock` - Test with mock server
- `task hex-viewer` - Hex viewer example

### Releases
- `task git-tag` - Create git tag
- `task release` - Create and push release tag

## Documentation Structure

```
docs/
├── taskfile/                    # This folder
│   ├── README.md               # This file
│   ├── TASKFILE_INTEGRATION.md # Original Taskfile integration
│   └── TASKFILE_V0.10_UPDATE.md # v0.10.x Taskfile updates
│
├── OPERATIONS.md               # Operations & troubleshooting guide
├── PERFORMANCE_TUNING.md       # Performance tuning guide
├── ARCHITECTURE.md             # System architecture
├── ... (other documentation)
```

## Related Documentation

### Release Documentation
See `releases/v0.10.0/` for:
- `RELEASE_NOTES.md` - Complete release notes
- `SUMMARY.md` - Executive summary
- `README.md` - Navigation guide
- `DEVELOPMENT_PLAN.md` - Development plan
- `V0_10_COMPLETION_REPORT.md` - Complete report
- `V0.10_FINAL_SUMMARY.md` - Final summary

### Project Documentation
See `docs/` for:
- `OPERATIONS.md` - Operations & troubleshooting
- `PERFORMANCE_TUNING.md` - Performance guide
- `ARCHITECTURE.md` - System design
- `CONFIG_REFERENCE.md` - Configuration reference
- `API_GUIDE.md` - API documentation
- Other documentation files

## Questions?

Refer to the relevant documentation file above or check the Taskfile.yml in the project root for the complete task definitions.
