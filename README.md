# zig-3270: TN3270 Terminal Emulator

A high-performance TN3270 (3270 terminal) emulator written in Zig with zero-dependency architecture and comprehensive protocol support.

## Overview

**zig-3270** is a terminal emulator that implements the TN3270 protocol for connecting to IBM mainframe systems (CICS, IMS, TSO). It provides full 3270 screen modeling, field management, and keyboard integration with a clean, modular codebase.

- **Language**: Pure Zig (no C dependencies)
- **Platform**: macOS, Linux (cross-compilation supported)
- **Test Coverage**: 60+ unit tests, 100% passing
- **Codebase**: ~3,038 lines, 23 modules

## Features

### Core Terminal Capabilities
- ✓ Full TN3270 protocol implementation
- ✓ Screen buffer modeling and updates
- ✓ Protected/unprotected field management
- ✓ Keyboard mapping and input handling
- ✓ Session management
- ✓ Hex viewer for protocol debugging

### Network
- ✓ TCP connection pooling
- ✓ Automatic reconnection
- ✓ Telnet command negotiation
- ✓ Non-blocking I/O

### Display
- ✓ Screen refresh optimization
- ✓ Cursor positioning
- ✓ Field highlighting
- ✓ Terminal attribute support

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
# Hex viewer demo
task hex-viewer

# Integration test with ghostty-vt
task test-ghostty

# Connect to real mainframe (mvs38j.com)
task test-connection
```

## Architecture

The codebase is organized into 5 layers:

```
┌─────────────────────────────────┐
│  Application Layer              │ main.zig, client.zig
├─────────────────────────────────┤
│  Domain Layer                   │ screen.zig, field.zig, terminal.zig
├─────────────────────────────────┤
│  Protocol Layer                 │ protocol.zig, parser.zig, stream_parser.zig
├─────────────────────────────────┤
│  Network Layer                  │ connection.zig, telnet.zig
├─────────────────────────────────┤
│  Utilities & Tools              │ hex_viewer.zig, keyboard.zig, input.zig
└─────────────────────────────────┘
```

### Key Modules

| Module | Purpose | Tests |
|--------|---------|-------|
| `protocol.zig` | TN3270 constants and command definitions | - |
| `parser.zig` | Wire protocol parsing | 8 |
| `screen.zig` | Screen buffer model | 5 |
| `field.zig` | Field management and input | 6 |
| `terminal.zig` | Terminal state machine | 8 |
| `executor.zig` | Command execution | 6 |
| `hex_viewer.zig` | Protocol debugging tool | 7 |
| `input.zig` | Keyboard input handling | 4 |
| `data_entry.zig` | AID and data field processing | 5 |
| `command.zig` | Outbound command formatting | 5 |

## Testing

All tests use Zig's built-in testing framework (`std.testing`). Tests are organized into three categories:

### Running Tests

```bash
# Run all tests (unit + integration + benchmarks)
task test

# Run quick unit tests only (fast feedback)
task test-unit

# Run integration tests (end-to-end workflows)
task test-integration

# Run performance benchmarks (throughput measurements)
task test-benchmark

# Pre-commit validation (format check + all tests)
task check
```

### Test Coverage

- **120+ total tests** organized by module and category
- **100% pass rate**
- **Unit tests** (60+): Individual functions, happy/error cases
- **Integration tests** (7): End-to-end workflows combining multiple modules
- **Stress tests** (4): Large files (10KB-100KB) for hex_viewer
- **Performance benchmarks** (6): Parser, executor, field management throughput

### Test Organization

- `src/*_test.zig` - Unit tests for each module
- `src/integration_test.zig` - End-to-end e2e tests
- `src/benchmark.zig` - Performance benchmarks

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

### Not Yet Implemented

- EBCDIC encoding (ASCII only)
- Advanced structured fields (LU3 printing)
- Session persistence
- Color attributes

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

- **Memory-efficient**: Arena allocators for temporary data
- **Fast parsing**: Single-pass protocol parser
- **Minimal allocations**: Reusable buffers in hot paths

## Contributing

This project follows strict TDD and code quality disciplines:

1. All code changes must have passing tests
2. No behavioral changes mixed with refactoring
3. Code must pass `task fmt` check
4. Commits follow conventional commit format

See AGENTS.md for detailed development guidelines.

## References

- [TN3270 Protocol Specification](docs/) (in progress)
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design (in progress)
- [GHOSTTY_INTEGRATION.md](docs/GHOSTTY_INTEGRATION.md) - VT integration
- [HEX_VIEWER.md](docs/HEX_VIEWER.md) - Hex viewer documentation

## License

MIT

## Roadmap

See [TODO.md](TODO.md) for detailed roadmap and priorities:

- **Month 1**: Complete documentation and refactoring (reduce coupling)
- **Month 2**: Add EBCDIC support and session persistence
- **Month 3**: Performance optimization and CI/CD setup
