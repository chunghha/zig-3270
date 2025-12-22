# zig-3270: TN3270 Terminal Emulator

A high-performance TN3270 (3270 terminal) emulator written in Zig with comprehensive protocol support and optional terminal integration.

## Overview

**zig-3270** is a terminal emulator that implements the TN3270 protocol for connecting to IBM mainframe systems (CICS, IMS, TSO). It provides full 3270 screen modeling, field management, and keyboard integration with a clean, modular architecture.

- **Language**: Pure Zig with optional libghostty-vt integration
- **Platform**: macOS, Linux (cross-compilation supported)
- **Test Coverage**: 250+ tests, 100% passing
- **Codebase**: ~10,500 lines, 70 modules
- **Status**: v0.10.2 - Production-hardened with enterprise features, monitoring, and advanced debugging

## Dependencies

### Required
- **Zig** 0.15.2 or later

### Optional
- **libghostty-vt**: For advanced terminal integration and VT emulation
  - Lazily loaded (only used if available)
  - Adds visual test capabilities
  - See [GHOSTTY_INTEGRATION.md](docs/GHOSTTY_INTEGRATION.md)

## Features

### Core Terminal Capabilities
- ✓ Full TN3270 protocol implementation
- ✓ EBCDIC character encoding/decoding
- ✓ Screen buffer modeling and updates
- ✓ Protected/unprotected field management
- ✓ Keyboard mapping and input handling
- ✓ Session management
- ✓ Hex viewer for protocol debugging
- ✓ Error context with recovery suggestions
- ✓ Configurable debug logging

### Network & Resilience
- ✓ TCP connection pooling
- ✓ Automatic reconnection with exponential backoff
- ✓ Telnet command negotiation
- ✓ Non-blocking I/O
- ✓ Connection statistics and health monitoring
- ✓ Configurable timeouts

### Display & Rendering
- ✓ Screen refresh optimization
- ✓ Cursor positioning
- ✓ Field highlighting
- ✓ Terminal attribute support
- ✓ ANSI color mapping
- ✓ Screen history & scrollback buffer

### Performance Optimizations
- ✓ Buffer pooling (30-50% allocation reduction)
- ✓ Field storage externalization (N→1 allocations)
- ✓ Field lookup caching (O(n)→O(1) optimization)
- ✓ Allocation tracking with precise memory metrics
- ✓ Comprehensive benchmark suite (19 performance tests)

### User Features
- ✓ CLI interface with command-line argument parsing
- ✓ Interactive terminal mode with keyboard input and display refresh
- ✓ Keyboard configuration system with JSON config files
- ✓ Session persistence with crash recovery
- ✓ Multiple connection profiles
- ✓ Session recording and playback
- ✓ Screen history & scrollback buffer navigation
- ✓ ANSI color support for field attributes
- ✓ Error recovery guidance
- ✓ Multi-session pool management (v0.9.0+)
- ✓ Load balancing with automatic failover (v0.9.0+)
- ✓ Audit logging and compliance tracking (v0.9.0+)
- ✓ REST API with HTTP interface (v0.9.0+)

### Advanced Debugging
- ✓ Protocol snooper for event capture and analysis
- ✓ State inspector for dumping and JSON export
- ✓ CLI profiler for performance bottleneck identification
- ✓ Session auto-save with configurable intervals

## Quick Start

### Installation

```bash
git clone https://github.com/yourusername/zig-3270
cd zig-3270
```

### Building

```bash
# Standard build
task build

# Or using zig directly
zig build

# Format code
task fmt

# Run tests
task test

# Full check (format + test)
task check
```

### Running

```bash
# Run emulator
task run

# Hex viewer demo
task hex-viewer

# Integration test with ghostty-vt
task test-ghostty

# Connect to real mainframe (mvs38j.com)
task test-connection

# Test with mock server
task mock-server  # (terminal 1)
task test-mock     # (terminal 2)
```

### Development

```bash
# Development workflow
task dev                    # format → test → build

# Code metrics
task loc                    # whole repo
task loc:zig                # src/ only

# Performance testing
task benchmark               # all 19 benchmarks
task benchmark:report         # performance analysis
task profile                 # detailed profiling
```

## Architecture

The codebase follows a **5-layer architecture with facade pattern** for minimal coupling:

```
┌─────────────────────────────────┐
│  Application Layer              │ main.zig, emulator.zig, client.zig
├─────────────────────────────────┤
│  Domain Layer Facade            │ domain_layer.zig (consolidates 5 modules)
│    ├─ Screen & Fields           │ screen.zig, field.zig, terminal.zig
│    ├─ Execution                 │ executor.zig, data_entry.zig  
│    └─ Session & History         │ session_storage.zig, screen_history.zig
├─────────────────────────────────┤
│  Protocol Layer Facade          │ protocol_layer.zig (consolidates 5 modules)
│    ├─ Core Protocol             │ protocol.zig, command.zig
│    ├─ Parsing                   │ parser.zig, stream_parser.zig, parse_utils.zig
│    └─ Optimization              │ parser_optimization.zig
├─────────────────────────────────┤
│  Network Layer                  │ client.zig, network_resilience.zig, mock_server.zig
├─────────────────────────────────┤
│  Performance Layer              │ buffer_pool.zig, field_storage.zig, field_cache.zig
│    ├─ Tracking                  │ allocation_tracker.zig, profiler.zig
│    └─ Benchmarking              │ benchmark*.zig (4 files)
├─────────────────────────────────┤
│  Utilities & Tools              │ keyboard_config.zig, renderer.zig, attributes.zig
│    ├─ Character Support         │ ebcdic.zig, ansi_colors.zig
│    ├─ Debugging                 │ debug_log.zig, error_context.zig, hex_viewer.zig
│    └─ Integration               │ ghostty_vt*.zig, integration_test.zig
└─────────────────────────────────┘
```

### Performance Optimizations Implemented

| Optimization | Module | Impact | Status |
|-------------|---------|---------|--------|
| Buffer Pooling | `buffer_pool.zig` | 30-50% allocation reduction | ✅ Implemented |
| Field Storage | `field_storage.zig` | N→1 allocations | ✅ Implemented |
| Field Caching | `field_cache.zig` | O(n)→O(1) lookups | ✅ Implemented |
| Allocation Tracking | `allocation_tracker.zig` | Precise memory metrics | ✅ Implemented |

### Key Modules

| Module | Purpose | Tests | Performance |
|--------|---------|-------|-------------|
| `protocol_layer.zig` | Protocol facade (5 modules) | - | 500+ MB/s parser |
| `domain_layer.zig` | Domain facade (5 modules) | - | Reduced coupling by 67% |
| `emulator.zig` | High-level orchestrator | - | 4 imports vs 12 (67% reduction) |
| `buffer_pool.zig` | Generic buffer management | 3 | Pool reuse rates up to 50%+ |
| `field_storage.zig` | Externalized field data | 5 | Single allocation per screen |
| `field_cache.zig` | Field lookup optimization | 4 | O(1) cache hits for hot paths |
| `benchmark*.zig` | Performance testing | 19 | Comprehensive coverage |

## Testing

All tests use Zig's built-in testing framework (`std.testing`) with **TDD methodology**. Tests are organized into four categories:

### Running Tests

```bash
# Core testing tasks
task test                    # all tests (unit + integration)
task test:unit               # unit tests only (fastest)
task test:integration          # integration tests only
task check                   # format check + core tests (pre-commit)

# Performance testing  
task benchmark               # all 19 benchmark tests
task benchmark:throughput    # 6 throughput benchmarks
task benchmark:enhanced      # 6 allocation tracking tests
task benchmark:optimization   # 3 optimization impact tests
task benchmark:comprehensive # 4 real-world scenario tests
task benchmark:report        # complete performance analysis
task profile                # detailed performance profiling
```

### Test Coverage

- **192+ total tests** organized by module and category
- **100% pass rate** across all test categories
- **Unit tests**: Individual functions, happy/error cases
- **Integration tests** (12+): End-to-end workflows combining multiple modules
- **Performance benchmarks** (19): Comprehensive performance analysis
  - Throughput tests (6): Parser, executor, field management
  - Enhanced tests (6): With allocation tracking
  - Optimization tests (3): Before/after comparisons
  - Comprehensive tests (4): Real-world scenarios
- **CLI & Feature tests** (40+): Command-line interface, interactive mode, debugging tools, user features

### Test Organization

- `src/*_test.zig` - Unit tests for each module
- `src/integration_test.zig` - End-to-end e2e tests
- `src/benchmark*.zig` - Performance benchmark suite (4 files)
  - `benchmark.zig` - Original throughput tests
  - `benchmark_enhanced.zig` - Allocation tracking tests
  - `benchmark_optimization_impact.zig` - Optimization impact tests
  - `benchmark_comprehensive.zig` - Real-world scenario tests

## Development

### TDD Workflow

1. Write a failing test describing the desired behavior
2. Implement the minimal code to make the test pass
3. Run `task test` to verify
4. Run `task fmt` to format code
5. Commit when tests pass using conventional commits

### Commit Format

```
feat(hex_viewer): add configurable bytes per line
fix(parser): handle 0x5B escape sequences correctly
refactor: extract parsing utilities to common module
test: add integration tests for screen updates
docs: document protocol.zig constants
```

### Code Quality Standards

- Follow Zig conventions: `snake_case` for functions/variables, `PascalCase` for types
- Write clear, explicit code—no hidden state
- Separate structural changes (refactoring) from behavioral changes
- Keep functions small and focused on a single responsibility
- Use error union types (`Type!Error`) for operations that may fail

## Protocol Support

### Supported Commands

- **3270 Data Stream**: Read Modified Fields (RMF), Write, Write Structured Field (WSF)
- **Field Attributes**: Protected, hidden, intensified, auto-skip, numeric-only
- **Keyboard Macros**: Customizable key bindings
- **Telnet Negotiation**: IAC commands, session negotiation

### Quality Assurance
- ✓ Memory and timing profiler
- ✓ Performance benchmarks (500+ MB/s parser, 2000+ cmd/ms)
- ✓ Comprehensive error handling
- ✓ Full test coverage (121+ tests)

### Implemented Features (v0.5.1 - v0.10.2)

**v0.5.1**:
- Core architecture with 5-layer design and facade pattern
- EBCDIC encoding/decoding with round-trip conversion
- Error handling with context and recovery suggestions
- Debug logging system with per-module configuration
- Performance profiling and memory tracking
- Buffer pooling, field storage, and field caching optimizations

**v0.6.0**:
- Full CLI interface with connection profiles and session recording
- Interactive terminal mode with keyboard input and real-time display
- Advanced debugging: protocol snooper, state inspector, CLI profiler
- Session auto-save with configurable intervals

**v0.7.0**:
- Session persistence with crash recovery
- Screen history & scrollback buffer with navigation
- ANSI color support and field attribute mapping
- Keyboard mapping configuration system
- Network resilience with connection pooling and auto-reconnect
- Comprehensive documentation (USER_GUIDE, API_GUIDE, CONFIG_REFERENCE)
- Protocol extensions (field validation, telnet negotiation, charset support)
- Example programs for common use cases

**v0.9.0**:
- Multi-session pool management for concurrent connections
- Load balancing with multiple strategies (round-robin, weighted, least-connection)
- Automatic failover and health monitoring
- Comprehensive audit logging and compliance tracking (SOC2, HIPAA, PCI-DSS)
- REST API with full CRUD operations and webhook support
- Enterprise deployment guide and monitoring setup

**v0.10.0**:
- Stability regression testing (33 tests)
- Enhanced error messages with error codes and recovery guidance
- Logging clarity with JSON output format support
- Production hardening with security review and resource limits
- Metrics export for Prometheus and JSON monitoring systems
- Disaster recovery testing framework

**v0.10.1**:
- Error message improvements with standardized error codes
- Logging configuration via environment variables
- Configuration validation with clear error reporting

**v0.10.2**:
- Security audit and input validation
- Resource management with configurable limits
- Operational monitoring and metrics export
- Disaster recovery testing suite

## Examples

### Basic Connection

```zig
const connection = try TelnetConnection.init(allocator, "mvs38j.com", 23);
defer connection.deinit();

try connection.connect();
const screen = try ScreenBuffer.init(allocator, 24, 80);
defer screen.deinit();

// Handle protocol negotiation and screen updates...
```

### Using the Hex Viewer

```bash
# View a binary file side-by-side
./zig-out/bin/hex_viewer <file> [--bytes 16]
```

## Performance

### Baseline Metrics
- **Parser throughput**: 500+ MB/s with <1ms command latency
- **Stream processing**: 2000+ commands/ms for 10KB buffers
- **Memory efficiency**: 82% allocation reduction with optimizations
- **Screen rendering**: 50+ MB/s throughput with zero-copy operations

### Optimizations Implemented
- **Buffer pooling**: Generic reusable buffer pools (30-50% allocation reduction)
- **Field storage**: Externalized field data (N→1 allocations per screen)
- **Field caching**: O(n)→O(1) lookup optimization for hot paths
- **Allocation tracking**: Precise memory usage monitoring with detailed metrics
- **Connection resilience**: Pooling, auto-reconnection, exponential backoff

### Memory Management
- **Arena allocators**: Temporary data with automatic cleanup
- **Single-pass parsing**: Zero-copy protocol processing
- **Reusable buffers**: Hot path optimization with pooling
- **Explicit memory management**: Deterministic resource usage

## Contributing

This project follows strict TDD and code quality disciplines:

1. All code changes must have passing tests
2. No behavioral changes mixed with refactoring
3. Code must pass `task fmt` check
4. Commits follow conventional commit format

See AGENTS.md for detailed development guidelines.

## Documentation

### Getting Started
- [QUICKSTART.md](QUICKSTART.md) - Quick reference and development workflow
- [AGENTS.md](AGENTS.md) - Development methodology and guidelines

### Core Documentation
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design and module structure
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) - Performance profiling and optimization guide
- [docs/PROTOCOL.md](docs/PROTOCOL.md) - TN3270 protocol specification

### User & API Documentation
- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) - User documentation and terminal usage
- [docs/API_GUIDE.md](docs/API_GUIDE.md) - Developer API and embedding guide
- [docs/CONFIG_REFERENCE.md](docs/CONFIG_REFERENCE.md) - Configuration options and CLI flags

### Operations & Deployment
- [docs/OPERATIONS.md](docs/OPERATIONS.md) - Operations and troubleshooting guide (v0.10.3)
- [docs/PERFORMANCE_TUNING.md](docs/PERFORMANCE_TUNING.md) - Performance tuning guide (v0.10.3)
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) - Deployment guide (v0.9.0+)
- [docs/INTEGRATION_ADVANCED.md](docs/INTEGRATION_ADVANCED.md) - Advanced integration patterns (v0.10.0+)

### Specialized Topics
- [docs/GHOSTTY_INTEGRATION.md](docs/GHOSTTY_INTEGRATION.md) - VT integration details
- [docs/HEX_VIEWER.md](docs/HEX_VIEWER.md) - Hex viewer utility documentation
- [docs/CI_CD.md](docs/CI_CD.md) - CI/CD pipeline and release process
- [docs/taskfile/INDEX.md](docs/taskfile/INDEX.md) - Taskfile documentation (v0.10.x tasks)

### Examples & Resources
- [examples/INDEX.md](examples/INDEX.md) - Example programs and usage guide
- [releases/v0.10.0/INDEX.md](releases/v0.10.0/INDEX.md) - v0.10.0 release archive and notes

## Releases

This project uses [Semantic Versioning](https://semver.org/). See [AGENTS.md](AGENTS.md) for release process.

### Creating a Release

```bash
# Verify everything works
task check      # Tests + format check
task build      # Build binaries
task loc        # Check code metrics

# Create version tag
git tag -a v0.2.0 -m "Release v0.2.0 - Your message"
git push origin v0.2.0

# GitHub Actions automatically:
# 1. Runs tests on Ubuntu and macOS
# 2. Builds release binaries
# 3. Creates GitHub Release with assets
```

## License

MIT

## Development Workflow

### TDD Process
1. **Red**: Write failing test describing desired behavior
2. **Green**: Implement minimal code to make test pass
3. **Refactor**: Improve structure while keeping tests green
4. **Validate**: Run `task check` (format + test)

### Quality Standards
- All code changes require passing tests
- Structural changes separated from behavioral changes
- Code must pass `task fmt` formatting check
- Conventional commit format required
- Performance validated through benchmark suite

## Project Status

### Completed Optimizations ✓
- **Priority E**: Buffer pooling, field storage, parser optimization
- **Performance**: 82% allocation reduction, 500+ MB/s throughput
- **Quality**: Comprehensive test suite, allocation tracking

### Future Opportunities
- Advanced structured fields (LU3 printing)
- SIMD screen operations (if applicable)
- Custom allocator for protocol buffers
- Zero-copy network parsing
- JIT command compilation

## Documentation


