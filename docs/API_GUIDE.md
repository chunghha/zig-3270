# zig-3270: API Guide

Developer guide for embedding zig-3270 in Zig applications.

## Table of Contents

- [Integration Basics](#integration-basics)
- [Core APIs](#core-apis)
- [Protocol Layer](#protocol-layer)
- [Domain Layer](#domain-layer)
- [Network Layer](#network-layer)
- [Error Handling](#error-handling)
- [Debugging & Profiling](#debugging--profiling)
- [Code Examples](#code-examples)
- [Best Practices](#best-practices)

---

## Integration Basics

### Adding zig-3270 as a Library

#### Step 1: Add to build.zig.zon

```zig
.{
    .name = "my-app",
    .version = "0.1.0",
    .dependencies = .{
        .zig_3270 = .{
            .url = "https://github.com/chunghha/zig-3270/archive/v0.7.0.tar.gz",
            .hash = "...",
        },
    },
}
```

#### Step 2: Configure build.zig

```zig
const zig_3270 = b.dependency("zig_3270", .{
    .target = target,
    .optimize = optimize,
});

exe.addModule("zig3270", zig_3270.module("root"));
```

#### Step 3: Use in Your Code

```zig
const zig3270 = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use zig3270 APIs
}
```

---

## Core APIs

### TelnetConnection

The main client for connecting to TN3270 servers.

```zig
const TelnetConnection = zig3270.client.TelnetConnection;

// Initialize
var conn = try TelnetConnection.init(allocator);
defer conn.deinit();

// Connect
try conn.connect("mainframe.example.com", 23);

// Send command
const cmd = zig3270.protocol.Command{
    .code = .erase_write,
    .data = &.{0x11, 0x00, 0x00}, // Set buffer address to (0,0)
};
try conn.send_command(cmd);

// Receive response
const response = try conn.read_response(5000); // 5 second timeout
defer allocator.free(response);

// Close connection
conn.close();
```

### Emulator

High-level terminal emulation.

```zig
const Emulator = zig3270.emulator.Emulator;

// Initialize 24x80 screen
var emulator = try Emulator.init(allocator, 24, 80);
defer emulator.deinit();

// Process a command
const cmd = zig3270.protocol.Command{ /* ... */ };
try emulator.process_command(cmd);

// Read screen
const char = try emulator.read_char(0, 0); // Row 0, Col 0

// Write screen
try emulator.write_char(5, 10, 'A');

// Get field count
const field_count = emulator.field_count();

// Iterate fields
for (emulator.list_fields()) |field| {
    std.debug.print("Field at ({},{})\n", .{field.start_address.row, field.start_address.col});
}
```

### Screen & Fields

```zig
const Screen = zig3270.screen.Screen;
const FieldManager = zig3270.field.FieldManager;

var screen_buffer = try Screen.ScreenBuffer.init(allocator, 24, 80);
defer screen_buffer.deinit();

var field_manager = FieldManager.init(allocator);
defer field_manager.deinit();

// Add field
const field = zig3270.field.Field{
    .start_address = .{ .row = 0, .col = 0 },
    .length = 80,
    .attribute = .{ .protected = true },
};
try field_manager.add_field(field);

// Get field
const retrieved = field_manager.fields[0];
```

---

## Protocol Layer

The protocol layer handles TN3270 protocol specifics.

### Protocol Types

```zig
const Protocol = zig3270.protocol;

// Command codes
const cmd_code = Protocol.CommandCode.write;
const cmd_code2 = Protocol.CommandCode.erase_write;

// Order codes
const order_code = Protocol.OrderCode.set_buffer_address;
const order_code2 = Protocol.OrderCode.start_field;

// Field attributes
const attr = Protocol.FieldAttribute{
    .protected = true,
    .numeric = false,
    .hidden = false,
    .intensified = true,
    .modified = false,
};

// Address (row, col)
const addr = Protocol.Address{ .row = 5, .col = 10 };
```

### Command Parsing

```zig
const CommandParser = zig3270.command.CommandParser;

var parser = CommandParser.init(allocator);
defer parser.deinit(); // if allocations needed

// Parse command from buffer
const raw = [_]u8{ 0x01, 0x11, 0x00, 0x00, 0x48, 0x65, 0x6C, 0x6C, 0x6F };
const cmd = try parser.parse_command(&raw);
defer cmd.deinit(allocator);

std.debug.print("Command code: {}\n", .{cmd.code}); // .write
std.debug.print("Data length: {}\n", .{cmd.data.len}); // 6

// Parse orders within command
const orders = try parser.parse_orders(cmd.data);
defer orders.deinit();

for (orders.items) |order| {
    std.debug.print("Order: {}\n", .{order.code});
}
```

### EBCDIC Encoding

```zig
const ebcdic = zig3270.ebcdic;

// Encode single byte
const ebcdic_byte = try ebcdic.encode_byte('A'); // Returns EBCDIC 0xC1
std.debug.print("{x:02}\n", .{ebcdic_byte});

// Decode single byte
const ascii_byte = ebcdic.decode_byte(0xC1); // Returns ASCII 'A'
std.debug.print("{c}\n", .{ascii_byte});

// Encode buffer
var ascii_data = "Hello".*;
var ebcdic_buffer: [5]u8 = undefined;
const encoded_len = try ebcdic.encode(&ascii_data, &ebcdic_buffer);

// Decode buffer
const decoded_len = try ebcdic.decode(&ebcdic_buffer, &ascii_data);

// Allocating version
const encoded_alloc = try ebcdic.encode_alloc(allocator, "Test");
defer allocator.free(encoded_alloc);
```

---

## Domain Layer

The domain layer handles terminal and screen semantics.

### Executor

Executes commands on the emulator state.

```zig
const Executor = zig3270.executor.Executor;

var executor = Executor.init(allocator, &screen_buffer, &field_manager);

// Execute command
try executor.execute(command);

// After execution, screen_buffer and field_manager are updated
```

### Renderer

Renders terminal state for display.

```zig
const Renderer = zig3270.renderer.Renderer;

var renderer = Renderer.init(allocator);
defer renderer.deinit();

// Render screen
const rendered = try renderer.render(&screen_buffer, &field_manager);
defer allocator.free(rendered);

// rendered is ANSI-formatted string ready for display
std.io.getStdOut().writer().print("{s}\n", .{rendered});
```

### Terminal Abstraction

```zig
const Terminal = zig3270.terminal.Terminal;

var terminal = Terminal.init(allocator);
defer terminal.deinit();

// Set cursor position
terminal.set_cursor(5, 10);

// Get cursor position
const cursor = terminal.get_cursor();
std.debug.print("Cursor at ({},{})\n", .{cursor.row, cursor.col});

// Clear screen
terminal.clear();
```

---

## Network Layer

### Client Connection

```zig
const client = zig3270.client;

// Create connection
var conn = try client.TelnetConnection.init(allocator);
defer conn.deinit();

// Connect with timeout
try conn.connect("mainframe.example.com", 23);

// Set timeouts
conn.set_timeouts(5000, 5000); // 5s read/write timeout

// Send raw data
try conn.write_raw(&[_]u8{ 0xFF, 0xFB, 0x01 });

// Read raw data
const data = try conn.read_raw(1024, 5000);
defer allocator.free(data);

// Disconnect
conn.close();
```

### Connection Pooling

```zig
const network = zig3270.network_resilience;

var pool = network.ConnectionPool.init(allocator, 10); // Pool size 10
defer pool.deinit();

// Get connection
var conn = try pool.acquire("mainframe.example.com", 23);
defer pool.release(conn);

// Connection reused from pool for next request
var conn2 = try pool.acquire("mainframe.example.com", 23);
```

### Resilient Client

```zig
const ResilientClient = network.ResilientClient;

var resilient = try ResilientClient.init(allocator);
defer resilient.deinit();

// Configure retries
resilient.max_retries = 3;
resilient.base_delay_ms = 100;

// Send with auto-retry
const data = try resilient.send_with_retry(
    "mainframe.example.com",
    23,
    command_bytes,
    5000
);
defer allocator.free(data);
```

---

## Error Handling

### Structured Error Context

```zig
const error_context = zig3270.error_context;

// Handle parse errors with context
const parse_err = error_context.ErrorContext.ParseError{
    .kind = .invalid_command_code,
    .position = 5,
    .buffer_size = 100,
    .expected = "valid command code (0x01, 0x05, 0x06, ...)",
};

// Get formatted error message
const msg = try parse_err.message(allocator);
defer parse_err.deinit(msg, allocator);
std.debug.print("Error: {s}\n", .{msg});

// Field errors
const field_err = error_context.ErrorContext.FieldError{
    .kind = .invalid_attribute,
    .field_index = 3,
    .field_position = .{ .row = 5, .col = 10 },
    .details = "Protected field contains invalid attribute byte",
};

// Connection errors
const conn_err = error_context.ErrorContext.ConnectionError{
    .kind = .read_timeout,
    .timeout_ms = 5000,
    .bytes_received = 0,
};
```

### Error Recovery

```zig
// Try-catch pattern
const result = blk: {
    const conn = try client.TelnetConnection.init(allocator);
    defer conn.deinit();
    
    try conn.connect("mainframe.example.com", 23);
    break :blk try conn.read_response(5000);
} catch |err| {
    std.debug.print("Connection failed: {}\n", .{err});
    // Handle error
    if (err == error.ConnectionRefused) {
        // Try alternate server
    } else if (err == error.Timeout) {
        // Retry with longer timeout
    }
};
```

---

## Debugging & Profiling

### Debug Logging

```zig
const debug_log = zig3270.debug_log;

// Set global log level
debug_log.DebugLog.set_level(.info);

// Set module-specific level
debug_log.DebugLog.set_module_level(.parser, .trace);

// Log messages
debug_log.DebugLog.error_log(.parser, "Parse failed at position {}", .{pos});
debug_log.DebugLog.info(.executor, "Executing command code: {x}", .{cmd_code});
debug_log.DebugLog.debug_log(.client, "Connected to {s}:{}", .{host, port});
```

### Profiling

```zig
const profiler = zig3270.profiler;

var prof = profiler.Profiler.init(allocator);
defer prof.deinit();

// Record allocations
prof.record_alloc(1024);
prof.record_free(512);

// Time operations
{
    var scope = prof.scope("parse");
    defer scope.end();
    // ... parsing code ...
}

// Print reports
var stdout = std.io.getStdOut().writer();
try prof.print_memory_report(stdout);
try prof.print_timing_report(stdout);
```

### Protocol Snooping

```zig
const snooper = zig3270.protocol_snooper;

var snooper_inst = snooper.ProtocolSnooper.init(allocator);
defer snooper_inst.deinit();

// Capture events
try snooper_inst.capture_command(&command_bytes);
try snooper_inst.capture_response(&response_bytes);

// Analyze
const analysis = snooper_inst.analyze_commands();
std.debug.print("Commands sent: {}\n", .{analysis.command_count});
std.debug.print("Data transferred: {} bytes\n", .{analysis.data_sent_bytes});

// Export log
try snooper_inst.export_log("protocol.log");
```

### State Inspection

```zig
const inspector = zig3270.state_inspector;

var state_insp = inspector.StateInspector.init(allocator);

// Dump state
const screen_dump = try state_insp.dump_screen_state(&screen_buffer);
defer allocator.free(screen_dump);

const field_dump = try state_insp.dump_field_state(&field_manager);
defer allocator.free(field_dump);

// Export as JSON
const json = try state_insp.export_to_json(&screen_buffer, &field_manager, false, null);
defer allocator.free(json);

// Parse and use JSON...
```

---

## Code Examples

### Example 1: Simple Connect and Read

```zig
const std = @import("std");
const zig3270 = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var conn = try zig3270.client.TelnetConnection.init(allocator);
    defer conn.deinit();

    std.debug.print("Connecting to mainframe...\n", .{});
    try conn.connect("mainframe.example.com", 23);

    std.debug.print("Reading initial screen...\n", .{});
    const response = try conn.read_response(5000);
    defer allocator.free(response);

    std.debug.print("Received {} bytes\n", .{response.len});

    conn.close();
}
```

### Example 2: Parse Command and Execute

```zig
const std = @import("std");
const zig3270 = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create emulator
    var emulator = try zig3270.emulator.Emulator.init(allocator, 24, 80);
    defer emulator.deinit();

    // Create command: Write with set buffer address
    var cmd_data = std.ArrayList(u8).init(allocator);
    defer cmd_data.deinit();

    try cmd_data.append(0x11); // Set Buffer Address
    try cmd_data.append(0x00); // Row 0
    try cmd_data.append(0x00); // Col 0
    try cmd_data.appendSlice("Hello");

    const cmd = zig3270.command.Command{
        .code = .write,
        .data = cmd_data.items,
    };

    try emulator.process_command(cmd);

    // Verify
    const ch = try emulator.read_char(0, 0);
    std.debug.print("Screen[0,0] = '{c}'\n", .{ch});
}
```

### Example 3: Full Transaction with Error Handling

```zig
const std = @import("std");
const zig3270 = @import("zig3270");

fn login(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    username: []const u8,
    password: []const u8,
) !void {
    var conn = zig3270.client.TelnetConnection.init(allocator) catch |err| {
        std.debug.print("Failed to create connection: {}\n", .{err});
        return err;
    };
    defer conn.deinit();

    conn.connect(host, port) catch |err| {
        std.debug.print("Failed to connect to {s}:{}: {}\n", .{host, port, err});
        return err;
    };
    defer conn.close();

    // Get login screen
    const login_screen = conn.read_response(5000) catch |err| {
        std.debug.print("Failed to read login screen: {}\n", .{err});
        return err;
    };
    defer allocator.free(login_screen);

    std.debug.print("Login screen received ({} bytes)\n", .{login_screen.len});

    // TODO: Send username and password
    // (Would involve parsing fields and sending data)
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try login(allocator, "mainframe.example.com", 23, "testuser", "testpass");
}
```

---

## Best Practices

### 1. Memory Management

```zig
// Always pair allocations with deferrals
const buffer = try allocator.alloc(u8, 1024);
defer allocator.free(buffer);

// Use ArenaAllocator for temporary allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp = try arena.allocator().alloc(u8, 1024);
// All temp allocations freed when arena deinitializes
```

### 2. Error Handling

```zig
// Use try for propagation up the call stack
const result = try someOperation();

// Use catch for specific handling
const result = someOperation() catch |err| {
    if (err == error.Timeout) {
        // Handle timeout specifically
    } else {
        return err;
    }
};

// Use ? operator carefully
var value = try mayFail() orelse 0; // Provide fallback
```

### 3. Connection Management

```zig
// Always close connections
var conn = try TelnetConnection.init(allocator);
defer conn.close();

// Set appropriate timeouts
conn.set_timeouts(5000, 10000); // 5s read, 10s write

// Handle reconnection
if (conn.read_response(5000)) |data| {
    // Process data
} else |err| {
    if (err == error.ConnectionLost) {
        // Reconnect
    }
}
```

### 4. Performance

```zig
// Use profile for performance analysis
var prof = Profiler.init(allocator);
defer prof.deinit();

// Profile hot paths
{
    var scope = prof.scope("critical_section");
    defer scope.end();
    // ... performance-critical code ...
}

// Review reports
try prof.print_timing_report(std.io.getStdOut().writer());
```

### 5. Testing

```zig
// Include comprehensive tests in your modules
test "feature description" {
    var allocator = std.testing.allocator;
    
    // Setup
    var instance = try MyStruct.init(allocator);
    defer instance.deinit();
    
    // Execute
    const result = try instance.doSomething();
    
    // Assert
    try std.testing.expectEqual(expected, result);
}
```

---

## Related Documentation

- **USER_GUIDE.md** - End-user documentation
- **docs/ARCHITECTURE.md** - System design and modules
- **docs/PROTOCOL.md** - TN3270 protocol specification
- **docs/PERFORMANCE.md** - Performance tuning and optimization
- **QUICKSTART.md** - Quick setup and testing

---

**zig-3270 v0.7.0** - TN3270 Terminal Emulator  
High-Performance • Type-Safe • Memory-Efficient
