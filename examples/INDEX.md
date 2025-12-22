# zig-3270 Examples

Working examples demonstrating zig-3270 features and APIs.

## Overview

These examples show how to use zig-3270 for common tasks:

1. **simple_connect.zig** - Connect to a mainframe and read the initial screen
2. **with_profiler.zig** - Profile connection with memory and timing metrics
3. **batch_commands.zig** - Send multiple commands in sequence
4. **screen_capture.zig** - Capture and inspect screen state
5. **rest_client.zig** - REST API client library with full session/audit/compliance features

## Building Examples

### Build All Examples

```bash
# From project root
zig build

# Executables will be in zig-cache/bin/
```

### Build Specific Example

```bash
# Build one example
zig build -Dexample=simple_connect
```

## Running Examples

### Example 1: Simple Connect

Basic connection to a mainframe:

```bash
./zig-cache/bin/zig-3270-example-simple --host mainframe.example.com --port 23
```

**Output:**
- Connection status
- Raw protocol data (hex and ASCII)
- Byte count

**What it demonstrates:**
- Creating TelnetConnection
- Connecting to server
- Reading raw protocol response

**Code size:** ~100 lines

### Example 2: With Profiler

Connect and measure performance:

```bash
./zig-cache/bin/zig-3270-example-profiler --host mainframe.example.com
```

**Output:**
- Memory usage (allocated, freed, peak)
- Timing for each operation
- Operation count and duration

**What it demonstrates:**
- Using Profiler for metrics
- Tracking allocations
- Measuring operation timing
- Generating reports

**Code size:** ~120 lines

### Example 3: Batch Commands

Send multiple commands in sequence:

```bash
./zig-cache/bin/zig-3270-example-batch \
  --host mainframe.example.com \
  --commands "SIGN ON,MENU,HELP"
```

**Output:**
- Command send/receive log
- Byte counts per command
- Success rate summary

**What it demonstrates:**
- Building command sequences
- Sequential request/response
- Batch processing
- Error handling

**Code size:** ~150 lines

### Example 4: Screen Capture

Capture and inspect screen state:

```bash
./zig-cache/bin/zig-3270-example-capture \
  --host mainframe.example.com \
  --output screen.txt
```

**Output:**
- Screen grid display
- Field information
- Exported file (if specified)

**What it demonstrates:**
- Capturing screen state
- Using StateInspector
- Field parsing
- File export

**Code size:** ~200 lines

### Example 5: REST API Client

RESTful HTTP client library for zig-3270 REST API:

```bash
./zig-cache/bin/zig-3270-example-rest-client
```

**Output:**
- Client library demonstration
- Supported operations and features
- Configuration options

**What it demonstrates:**
- REST API client types and configuration
- Session management operations
- Screen capture via REST API
- Input injection
- Session control (suspend, resume, migrate)
- Endpoint health checks
- Audit log querying
- Compliance reporting
- Authentication support (bearer token, basic auth)

**Code size:** ~600 lines (production-ready library)

**Features:**
- HttpConfig with bearer token and basic auth support
- RestClient with session management methods
- Type-safe request/response handling
- Support for all enterprise API endpoints
- Proper error handling and resource cleanup

## Common Options

All examples support these flags:

```bash
--host HOST          Mainframe hostname or IP (required, except help)
--port PORT          TCP port number (default: 23)
--help               Show usage information
```

## Typical Workflow

```bash
# 1. Test basic connectivity
./zig-cache/bin/zig-3270-example-simple --host mainframe.example.com

# 2. Profile performance
./zig-cache/bin/zig-3270-example-profiler --host mainframe.example.com

# 3. Capture screen
./zig-cache/bin/zig-3270-example-capture --host mainframe.example.com --output initial.txt

# 4. Send batch commands
./zig-cache/bin/zig-3270-example-batch --host mainframe.example.com --commands "cmd1,cmd2"

# 5. Use REST API client for enterprise features
./zig-cache/bin/zig-3270-example-rest-client
```

## Extending Examples

To create your own example:

1. Create `examples/my_example.zig`
2. Import zig-3270:
   ```zig
   const root = @import("zig3270");
   ```
3. Use the APIs documented in `docs/API_GUIDE.md`
4. Build with zig

Example template:

```zig
const std = @import("std");
const root = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Your code here
}
```

## Troubleshooting

### "Cannot connect"
- Verify host and port are correct
- Check firewall allows port 23
- Ensure mainframe is accessible

### "Module not found"
- Run `zig build` first
- Check build.zig references

### "Timeout reading response"
- Increase timeout value (default: 5000ms)
- Check network latency
- Verify mainframe is responsive

## API Reference

For detailed API documentation, see:

- **docs/API_GUIDE.md** - Full API reference
- **docs/USER_GUIDE.md** - End-user usage guide
- **docs/CONFIG_REFERENCE.md** - Configuration options
- **QUICKSTART.md** - Quick setup

## Key Modules Used

| Module | Purpose |
|--------|---------|
| `client` | TelnetConnection for network I/O |
| `emulator` | Terminal emulation |
| `protocol` | Protocol types and constants |
| `command` | Command parsing |
| `screen` | Screen buffer management |
| `field` | Field management |
| `profiler` | Performance profiling |
| `state_inspector` | State inspection and export |
| `session_pool` | Multi-session management |
| `load_balancer` | Session distribution |
| `audit_log` | Event logging for compliance |
| `rest_api` | HTTP REST API interface |
| `event_webhooks` | Event notifications |

## Performance Tips

1. **Reuse connections** - Keep connection open between commands
2. **Profile hot paths** - Use profiler to find bottlenecks
3. **Monitor memory** - Check allocations with profiler
4. **Batch operations** - Send multiple commands at once

## Next Steps

After running examples:

1. Read **docs/API_GUIDE.md** for complete API reference
2. Review **docs/USER_GUIDE.md** for user documentation
3. Check **docs/CONFIG_REFERENCE.md** for configuration
4. Study **docs/ARCHITECTURE.md** for system design

---

**zig-3270 v0.9.4** - Example Programs  
Enterprise • Production-Ready • Well-Documented
