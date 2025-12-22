# Quick Start Guide

## Building & Testing

```bash
# Run all checks (format + tests)
task check

# Core testing tasks
task test                    # all tests (unit + integration)
task test:unit              # unit tests only (fastest)
task test:integration         # integration tests only

# Development workflow
task dev                    # format → test → build
task fmt                    # format code
task build                  # build executable
task run                    # run emulator

# Performance testing
task benchmark               # all 19 performance benchmarks
task benchmark:report         # complete performance analysis
task profile                 # detailed performance profiling

# Code analysis
task loc                    # whole repo line count
task loc:zig                # src/ line count only

# View all available tasks
task --list
```

## Project Structure

```
src/
├── Core Protocol Layer
│   ├── protocol.zig          - Protocol definitions
│   ├── parser.zig            - Basic parsing
│   ├── stream_parser.zig      - Streaming parser
│   ├── command.zig           - Command types
│   └── data_entry.zig        - Field input handling
│
├── Domain Layer (Terminal & Display)
│   ├── screen.zig            - Screen buffer management
│   ├── field.zig             - Field definitions
│   ├── terminal.zig          - Terminal abstraction
│   ├── executor.zig          - Command execution
│   ├── renderer.zig          - Screen rendering
│   └── attributes.zig        - Field attributes
│
├── Network & I/O
│   ├── client.zig            - TN3270 client
│   ├── mock_server.zig       - Mock server for testing
│   └── ghostty_vt_terminal.zig - Terminal integration
│
├── Facades & Architecture
│   ├── protocol_layer.zig    - Protocol facade (reduces coupling)
│   ├── domain_layer.zig      - Domain facade (reduces coupling)
│   └── emulator.zig          - Main emulator (4 imports only)
│
├── Quality Assurance
│   ├── error_context.zig     - Structured error handling
│   ├── debug_log.zig         - Configurable logging
│   └── profiler.zig          - Memory & timing profiler
│
├── Features
│   ├── ebcdic.zig            - EBCDIC encoding/decoding
│   └── hex_viewer.zig        - Hex dump utility
│
└── Testing & Documentation
    ├── integration_test.zig   - End-to-end tests
    ├── benchmark.zig         - Performance benchmarks
    └── main.zig              - Entry point

docs/
├── ARCHITECTURE.md           - System design
├── PERFORMANCE.md            - Performance guide & optimization
├── HEX_VIEWER.md             - Hex viewer documentation
├── GHOSTTY_INTEGRATION.md    - Terminal integration details
├── PROTOCOL.md               - TN3270 protocol specification
└── CODEBASE_REVIEW.md        - Detailed code analysis
```

## Key Features

### EBCDIC Support
```zig
const ebcdic = @import("ebcdic.zig");

// Encode ASCII to EBCDIC
const ebcdic_byte = try ebcdic.Ebcdic.encode_byte(0x41); // 'A' -> 0xC1

// Decode EBCDIC to ASCII
const ascii_byte = ebcdic.Ebcdic.decode_byte(0xC1); // 0xC1 -> 'A'

// Convert buffers
try ebcdic.Ebcdic.encode(ascii_buffer, ebcdic_buffer);
try ebcdic.Ebcdic.decode(ebcdic_buffer, ascii_buffer);
```

### Debug Logging
```zig
const debug_log = @import("debug_log.zig");

// Initialize (optional)
debug_log.DebugLog.init(allocator);

// Set global level
debug_log.DebugLog.set_level(.info);

// Set module-specific level
debug_log.DebugLog.set_module_level(.parser, .trace);

// Log messages
debug_log.DebugLog.error_log(.parser, "Failed to parse: {s}", .{reason});
debug_log.DebugLog.info(.parser, "Parsed {d} commands", .{count});
debug_log.DebugLog.debug_log(.executor, "Executing command: {d}", .{code});
```

### Error Handling
```zig
const error_context = @import("error_context.zig");

// Parse error with context
const err = error_context.ErrorContext.ParseError{
    .kind = .end_of_buffer,
    .position = 5,
    .buffer_size = 10,
    .expected = "command code",
};

// Get error message with recovery suggestion
const msg = try err.message(allocator);
defer err.deinit(msg, allocator);
// Prints: "Unexpected end of buffer at position 5/10..."
```

### Performance Profiling
```zig
const profiler_mod = @import("profiler.zig");

var profiler = profiler_mod.Profiler.init(allocator);
defer profiler.deinit();

// Track allocations
profiler.record_alloc(1024);
profiler.record_free(512);

// Time operations
{
    var scope = profiler.scope("operation_name");
    defer scope.end();
    // ... do work
}

// Print reports
var stdout = std.io.getStdOut().writer();
try profiler.print_memory_report(stdout);
try profiler.print_timing_report(stdout);
```

## Testing

### Run Unit Tests
```bash
task test
```

### Run Integration Tests
```bash
task test-integration
```

### Run Benchmarks
```bash
task test-benchmark
```

### Test with Mock Server
```bash
# Terminal 1: Start mock server
task mock-server

# Terminal 2: Connect client
task test-mock
```

### Test with Real Mainframe
```bash
task test-connection
# or with custom host/port:
task test-connection -- <host> <port>
```

## Architecture Principles

### Facade Pattern
- **protocol_layer.zig**: Consolidates 5 protocol modules → single import
- **domain_layer.zig**: Consolidates 5 domain modules → single import
- **Result**: emulator.zig reduced from 12→4 imports (67% reduction)

### Layered Architecture
```
┌─────────────────────┐
│   Application       │ (main.zig)
├─────────────────────┤
│   Domain Layer      │ (facade: domain_layer.zig)
│   (Screen, Fields)  │
├─────────────────────┤
│   Protocol Layer    │ (facade: protocol_layer.zig)
│   (Commands, Parsing)
├─────────────────────┤
│   I/O Layer         │ (client.zig, network)
└─────────────────────┘
```

### Error Handling Strategy
- Use error union types (`!T`) for recoverable errors
- Use `try` for error propagation
- Use `catch` for specific error handling
- Provide context with structured error types (error_context.zig)

### Performance Hot Paths
See `docs/PERFORMANCE.md` for detailed analysis:
- Parser: 500+ MB/s (optimized, no allocations in loop)
- Stream Parser: 2000+ cmd/ms (minimal allocations)
- Executor: 50+ MB/s (direct address calculations)
- Field Navigation: O(field_count) (opportunity to cache)

## Development Workflow

### For Feature Development
1. Write a failing test
2. Implement minimal code to pass
3. Run `task check` to verify
4. Refactor for clarity (keep tests green)
5. Commit with conventional message

### For Bug Fixes
1. Write a test that reproduces the bug
2. Fix the implementation
3. Run `task check` to verify
4. Commit with `fix(module): description` message

### For Documentation
1. Update relevant documentation
2. Update README if significant change
3. Commit with `docs: description` message

## Conventional Commits

```bash
# New feature
git commit -m "feat(module): description"

# Bug fix
git commit -m "fix(module): description"

# Refactoring (no behavior change)
git commit -m "refactor: description"

# Testing
git commit -m "test(module): description"

# Documentation
git commit -m "docs: description"

# Build/maintenance
git commit -m "chore: description"

# Code formatting
git commit -m "style: description"
```

## Useful Files to Read

1. **TODO.md** - Project roadmap with completed features and next steps
2. **docs/ARCHITECTURE.md** - System design and module relationships
3. **docs/PERFORMANCE.md** - Performance analysis and optimization guide
4. **docs/USER_GUIDE.md** - Using the terminal emulator
5. **docs/API_GUIDE.md** - Embedding and programmatic usage
6. **AGENTS.md** - Development methodology and standards

## Creating a Release

### Version Tags

The project uses semantic versioning with git tags:

```bash
# Create an annotated tag
git tag -a v0.2.0 -m "Release v0.2.0 - Quality Assurance & Performance"

# Push tag to trigger CI/release workflow
git push origin v0.2.0
```

GitHub Actions will automatically:
1. Run tests on Ubuntu and macOS
2. Build release binaries
3. Create GitHub Release with assets and documentation
4. Attach binaries for both platforms

### Pre-Release Checklist

```bash
# 1. Verify everything works
task check      # Tests must pass
task build      # Build must succeed
task loc        # Check metrics

# 2. Update documentation
# - Update TODO.md with completed work
# - Update relevant docs/

# 3. Create and push release tag
git tag -a v0.2.0 -m "Release message"
git push origin v0.2.0
# (GitHub Actions handles the rest)
```

See `docs/CI_CD.md` for detailed CI/CD documentation.

## Common Tasks

### Add a new test
```zig
test "feature description" {
    // 1. Setup
    var allocator = std.testing.allocator;
    
    // 2. Execute
    const result = try functionUnderTest(allocator);
    
    // 3. Assert
    try std.testing.expectEqual(expected, result);
}
```

### Profile memory usage
```bash
task test 2>&1 | grep "Profile\|Memory\|allocation"
```

### Check code metrics
```bash
task loc
```

### View test coverage
```bash
task test 2>&1 | grep "test "
```

## Troubleshooting

### Tests fail to compile
```bash
task fmt  # Format code first
zig build test  # Try building again
```

### Memory leaks in tests
- Check `defer` statements
- Use `std.testing.allocator` which detects leaks
- See `profiler.zig` for tracking allocations

### Performance regression
- Run benchmarks: `task test 2>&1 | grep benchmark`
- Profile with `profiler.zig`
- Check `docs/PERFORMANCE.md` for hot paths

## Next Steps

1. Read **docs/ARCHITECTURE.md** to understand system design
2. Review **docs/PERFORMANCE.md** for optimization opportunities
3. Check **TODO.md** for future development roadmap
4. Explore **docs/USER_GUIDE.md** for terminal usage
5. Run `task check` to verify everything works

---

**v0.7.0 Complete** ✓  
192+ tests passing • 9,232 lines • 62 modules • Production-ready  
CLI, Interactive Mode, Debugging Tools, Complete Documentation
