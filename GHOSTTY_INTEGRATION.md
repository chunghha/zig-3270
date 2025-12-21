# libghostty-vt Integration Guide

This project integrates [libghostty-vt](https://ghostty.org), a zero-dependency terminal emulation library from the Ghostty terminal emulator project.

## Testing from Command Line

### Visual Integration Test

Run the visual test demonstrating libghostty-vt capabilities:

```bash
# Using Taskfile
task test-ghostty

# Or directly via zig
zig build test-ghostty
```

This runs a comprehensive visual test that demonstrates:
- ✓ Terminal initialization (60×15, 40×10 configurations)
- ✓ Text output and rendering
- ✓ Line wrapping behavior
- ✓ Multi-terminal support
- ✓ VT sequence parsing
- ✓ Cursor positioning and styling

### Unit Tests

Run all unit tests including libghostty-vt integration tests:

```bash
# Using Taskfile
task test

# Or directly via zig
zig build test
```

### Development Workflow

Complete development cycle with format, test, and build:

```bash
task dev
```

This runs:
1. Code formatting (`task fmt`)
2. Unit tests (`task test`)
3. Build (`task build`)

## Architecture

```
src/
├── main.zig                      # Main app, imports ghostty_vt
├── ghostty_vt_example.zig        # Example API usage
└── ghostty_vt_visual_test.zig    # Visual test program
                                   (built separately)

build.zig                          # Defines test-ghostty step
                                   
build.zig.zon                      # Declares libghostty_vt dependency
                                   (lazy, fetched from ghostty repo)

Taskfile.yml                       # Test-ghostty task for CLI
```

## What's Tested

The visual test (`ghostty_vt_visual_test.zig`) demonstrates:

1. **Terminal Initialization**: Creating terminals with custom dimensions
2. **Text Output**: Printing strings to terminal buffer
3. **Line Wrapping**: Automatic wrapping at column boundaries
4. **Multi-Terminal**: Managing multiple terminal instances
5. **Terminal Capabilities**: VT sequence parsing, state management

## Integration Points

libghostty-vt is integrated at:

- **build.zig**: Declares dependency and build steps
- **build.zig.zon**: Specifies source URL and hash
- **src/main.zig**: Conditionally imports when available
- **src/ghostty_vt_example.zig**: Example API demonstrations
- **src/ghostty_vt_visual_test.zig**: Visual test executable

## Available Tasks

```bash
task               # List all available tasks
task build         # Build the 3270 emulator
task run           # Run the 3270 emulator
task test          # Run all unit tests
task test-ghostty  # Visual test of libghostty-vt integration
task fmt           # Format code with zig fmt
task check         # Pre-commit validation (format + test)
task clean         # Clean build artifacts
task dev           # Full dev workflow (format + test + build)
```

## Why libghostty-vt?

libghostty-vt provides:

- **Zero dependencies**: Runs without libc or external libraries
- **Real-world proven**: Used by Ghostty terminal emulator (40k+ GitHub stars)
- **Complete VT support**: Parses full range of terminal sequences
- **Fast parsing**: SIMD-optimized implementation
- **Cross-platform**: macOS, Linux, Windows, WebAssembly compatible
- **Clean API**: Simple Zig interface for terminal operations

## References

- [Ghostty project](https://github.com/ghostty-org/ghostty)
- [libghostty announcement](https://mitchellh.com/writing/libghostty-is-coming)
- [Ghostty documentation](https://ghostty.org/docs)
