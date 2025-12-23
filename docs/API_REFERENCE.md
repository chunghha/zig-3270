# Complete API Reference

**Version**: v0.11.3  
**Last Updated**: Dec 23, 2025  

This comprehensive API reference documents all public interfaces in the zig-3270 library. The library is organized into logical modules for protocol, domain, advanced features, and enterprise capabilities.

---

## Table of Contents

1. [Client API](#client-api)
2. [Screen & Terminal API](#screen--terminal-api)
3. [Field Management API](#field-management-api)
4. [Protocol Layer API](#protocol-layer-api)
5. [Advanced Features API](#advanced-features-api)
6. [Enterprise Features API](#enterprise-features-api)
7. [Error Handling & Logging](#error-handling--logging)
8. [C Bindings & Foreign Function Interface](#c-bindings--foreign-function-interface)

---

## Client API

The Client API provides TCP/TN3270 connection management to mainframe hosts.

### Module: `client`

**Import**: 
```zig
const client = @import("zig-3270").client;
```

### Types

#### `TelnetOption` (enum)
```zig
pub const TelnetOption = enum(u8) {
    transmit_binary = 0,        // 0x00 - Binary transmission mode
    echo = 1,                   // 0x01 - Echo option
    suppress_ga = 3,            // 0x03 - Suppress go-ahead
    terminal_type = 24,         // 0x18 - Terminal type negotiation
    end_of_record = 25,         // 0x19 - End of record
    naws = 31,                  // 0x1f - Negotiate About Window Size
};
```

Represents telnet option codes used during negotiation with the server.

#### `TelnetCommand` (enum)
```zig
pub const TelnetCommand = enum(u8) {
    se = 240,      // Subnegotiation End
    nop = 241,     // No Operation
    dm = 242,      // Data Mark
    brk = 243,     // Break
    ip = 244,      // Interrupt Process
    ao = 245,      // Abort Output
    ayt = 246,     // Are You There
    ec = 247,      // Erase Character
    el = 248,      // Erase Line
    ga = 249,      // Go Ahead
    sb = 250,      // Subnegotiation Begin
    will = 251,    // Will do option
    wont = 252,    // Won't do option
    do_cmd = 253,  // Do option
    dont = 254,    // Don't do option
    iac = 255,     // Interpret As Command (escape sequence marker)
};
```

Represents telnet command codes in protocol negotiation.

#### `Client` (struct)
```zig
pub const Client = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    stream: ?std.net.Stream,
    connected: bool,
    read_buffer: []u8,
    read_timeout_ms: u32 = 10000,
    write_timeout_ms: u32 = 5000,
    last_activity: i64 = 0,
    // ... private fields ...
};
```

Main client structure for managing TCP/TN3270 connections.

**Fields**:
- `allocator` - Memory allocator for dynamic allocations
- `host` - Hostname or IP address of the mainframe
- `port` - TCP port number (typically 23 for telnet)
- `stream` - Optional TCP stream connection
- `connected` - Boolean indicating connection state
- `read_buffer` - Buffer for reading data from network
- `read_timeout_ms` - Read operation timeout in milliseconds (default: 10000)
- `write_timeout_ms` - Write operation timeout in milliseconds (default: 5000)
- `last_activity` - Timestamp of last network activity

### Functions

#### `init(allocator, host, port) Client`
```zig
pub fn init(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
) Client
```

Initialize a new client without connecting.

**Parameters**:
- `allocator` - Memory allocator for buffers
- `host` - Hostname or IP address (string slice)
- `port` - TCP port number

**Returns**: Unconnected Client instance

**Example**:
```zig
const client = try Client.init(allocator, "mainframe.example.com", 23);
```

---

#### `connect() !void`
```zig
pub fn connect(self: *Client) !void
```

Establish TCP connection to the mainframe host.

**Parameters**: None (uses client's host and port)

**Errors**:
- `NetworkError.InvalidAddress` - Host is invalid
- `NetworkError.ConnectionFailed` - Cannot connect to host
- `NetworkError.TimeoutError` - Connection timed out
- `OutOfMemory` - Cannot allocate read buffer

**Example**:
```zig
var client = Client.init(allocator, "10.0.1.1", 23);
try client.connect();
```

---

#### `disconnect() void`
```zig
pub fn disconnect(self: *Client) void
```

Close TCP connection and clean up resources.

**Parameters**: None

**Side Effects**: Deallocates read buffer, closes TCP stream

**Example**:
```zig
defer client.disconnect();
```

---

#### `set_read_timeout(timeout_ms) void`
```zig
pub fn set_read_timeout(self: *Client, timeout_ms: u32) void
```

Configure read operation timeout.

**Parameters**:
- `timeout_ms` - Timeout in milliseconds

**Example**:
```zig
client.set_read_timeout(30000); // 30 second timeout
```

---

#### `set_write_timeout(timeout_ms) void`
```zig
pub fn set_write_timeout(self: *Client, timeout_ms: u32) void
```

Configure write operation timeout.

**Parameters**:
- `timeout_ms` - Timeout in milliseconds

---

#### `read() ![]u8`
```zig
pub fn read(self: *Client) ![]u8
```

Read data from the mainframe.

**Returns**: Slice of data read from network

**Errors**:
- `NotConnected` - Client not connected
- `ReadTimeout` - Read exceeded timeout
- `ConnectionLost` - Connection closed by host

**Example**:
```zig
const data = try client.read();
defer allocator.free(data);
```

---

#### `write(data) !void`
```zig
pub fn write(self: *Client, data: []const u8) !void
```

Write data to the mainframe.

**Parameters**:
- `data` - Bytes to send

**Errors**:
- `NotConnected` - Client not connected
- `WriteTimeout` - Write exceeded timeout
- `ConnectionLost` - Connection closed by host

**Example**:
```zig
try client.write("Hello");
```

---

#### `is_timed_out() bool`
```zig
pub fn is_timed_out(self: Client) bool
```

Check if the current read timeout has been exceeded.

**Returns**: True if no activity within timeout period

---

## Screen & Terminal API

The Screen API manages the 3270 display buffer (24×80 character grid).

### Module: `screen` and `terminal`

### Types

#### `Screen` (struct)
```zig
pub const Screen = struct {
    // 3270 screen is 24 rows × 80 columns
    buffer: [1920]u8,           // Main display buffer (24 * 80)
    modified_fields: [32]u8,    // Modified field flags
    protected_fields: [32]u8,   // Protected field flags
    cursor_position: u16,       // Current cursor offset (0-1919)
    is_protected: bool,         // If entire screen is protected
    auto_skip: bool,            // Auto-skip over protected fields
    // ... private fields ...
};
```

Represents the 3270 terminal screen buffer.

---

#### `Terminal` (struct)
```zig
pub const Terminal = struct {
    screen: Screen,
    renderer: Renderer,
    field_manager: FieldManager,
    allocator: std.mem.Allocator,
};
```

High-level terminal abstraction combining screen, rendering, and field management.

---

### Screen Functions

#### `Screen.init() Screen`
```zig
pub fn init() Screen
```

Initialize a blank 24×80 screen.

**Returns**: New Screen with buffer cleared

**Example**:
```zig
var screen = Screen.init();
```

---

#### `Screen.clear() void`
```zig
pub fn clear(self: *Screen) void
```

Clear entire screen to spaces.

---

#### `Screen.write(offset, text) !void`
```zig
pub fn write(self: *Screen, offset: u16, text: []const u8) !void
```

Write text at screen offset.

**Parameters**:
- `offset` - 0-1919, calculated as row×80 + col
- `text` - String to write

**Errors**:
- `OffsetOutOfBounds` - Offset >= 1920
- `TextTooLong` - Text extends beyond screen end

**Example**:
```zig
try screen.write(0, "Welcome to Mainframe");
```

---

#### `Screen.read(offset, length) []u8`
```zig
pub fn read(self: *Screen, offset: u16, length: u16) []u8
```

Read text from screen.

**Parameters**:
- `offset` - Starting offset
- `length` - Number of characters to read

**Returns**: Slice of screen buffer (no allocation)

---

#### `Screen.set_cursor(row, col) !void`
```zig
pub fn set_cursor(self: *Screen, row: u8, col: u8) !void
```

Position the cursor.

**Parameters**:
- `row` - 0-23
- `col` - 0-79

**Errors**:
- `CursorOutOfBounds` - Row >= 24 or col >= 80

---

#### `Screen.get_cursor() [2]u8`
```zig
pub fn get_cursor(self: *Screen) [2]u8
```

Get current cursor position as [row, col].

---

#### `Screen.to_string(allocator) ![]u8`
```zig
pub fn to_string(self: *Screen, allocator: std.mem.Allocator) ![]u8
```

Convert screen buffer to allocated string.

**Parameters**:
- `allocator` - Memory allocator

**Returns**: Allocated string (caller owns)

**Errors**:
- `OutOfMemory` - Cannot allocate result

---

## Field Management API

The Field API manages input/output fields on the 3270 screen.

### Module: `field` and `attributes`

### Types

#### `Field` (struct)
```zig
pub const Field = struct {
    id: u16,                      // Unique field identifier
    address: u16,                 // Offset on screen (0-1919)
    length: u16,                  // Field length in characters
    attributes: FieldAttributes,  // Field display/protection attributes
    data: []u8,                   // Field content (borrowed reference)
};
```

Represents a single 3270 field (input or output).

---

#### `FieldAttributes` (struct)
```zig
pub const FieldAttributes = struct {
    protected: bool = false,       // Cannot be modified by user
    numeric: bool = false,         // Only numeric input
    hidden: bool = false,          // Do not display
    intensity: bool = false,       // Bright/highlighted display
    underline: bool = false,       // Underlined text
    reverse_video: bool = false,   // Reverse video display
};
```

Bitfield for field display and input attributes.

---

#### `FieldManager` (struct)
```zig
pub const FieldManager = struct {
    allocator: std.mem.Allocator,
    fields: std.ArrayList(Field),
    next_id: u16 = 0,
    // ... private fields ...
};
```

Manages a collection of fields on the screen.

---

### Field Functions

#### `FieldManager.init(allocator) FieldManager`
```zig
pub fn init(allocator: std.mem.Allocator) FieldManager
```

Initialize empty field manager.

---

#### `FieldManager.add_field(address, length, attributes) !Field`
```zig
pub fn add_field(
    self: *FieldManager,
    address: u16,
    length: u16,
    attributes: FieldAttributes,
) !Field
```

Add a new field to the manager.

**Parameters**:
- `address` - Offset on screen
- `length` - Field length
- `attributes` - Display/protection attributes

**Returns**: Newly created Field

**Errors**:
- `OutOfMemory` - Cannot add field
- `OffsetOutOfBounds` - Address + length > 1920

---

#### `FieldManager.count() usize`
```zig
pub fn count(self: *FieldManager) usize
```

Get number of managed fields.

---

#### `FieldManager.get(id) ?Field`
```zig
pub fn get(self: *FieldManager, id: u16) ?Field
```

Get field by ID.

**Returns**: Field if found, null otherwise

---

#### `FieldManager.find_at(address) ?Field`
```zig
pub fn find_at(self: *FieldManager, address: u16) ?Field
```

Find field at screen offset.

---

#### `FieldManager.update_field(id, new_data) !void`
```zig
pub fn update_field(
    self: *FieldManager,
    id: u16,
    new_data: []const u8,
) !void
```

Update field content.

**Errors**:
- `FieldNotFound` - ID doesn't exist
- `DataTooLong` - Data exceeds field length

---

#### `FieldManager.deinit() void`
```zig
pub fn deinit(self: *FieldManager) void
```

Free all field resources.

---

## Protocol Layer API

The Protocol API handles TN3270 protocol parsing and command execution.

### Module: `protocol` (via `protocol_layer`)

### Types

#### `CommandCode` (enum)
```zig
pub const CommandCode = enum(u8) {
    erase_write = 0x05,              // Erase and write screen
    erase_write_alternate = 0x0d,    // Erase and write alternate
    erase_all_unprotected = 0x0f,    // Erase unprotected fields
    write = 0x01,                    // Write to screen
    read_buffer = 0x02,              // Read screen buffer
    // ... 30+ commands ...
};
```

3270 protocol command codes.

---

#### `OrderCode` (enum)
```zig
pub const OrderCode = enum(u8) {
    set_buffer_address = 0x11,       // Set write position
    start_field = 0x1d,              // Begin new field
    start_field_extended = 0x29,     // Extended field definition
    text = 0x41,                     // Plain text
    erase_unprotected_to_address = 0x12,
    // ... 10+ orders ...
};
```

3270 protocol order codes.

---

#### `FieldAttribute` (enum)
```zig
pub const FieldAttribute = enum(u8) {
    protected = 0x20,
    numeric = 0x04,
    hidden = 0x08,
    intensity = 0x01,
    underline = 0x02,
    reverse_video = 0x40,
};
```

3270 field attribute codes.

---

#### `Parser` (struct)
```zig
pub const Parser = struct {
    buffer: []const u8,
    offset: usize = 0,
    allocator: std.mem.Allocator,
};
```

Stateful parser for 3270 protocol data.

---

#### `Command` (struct)
```zig
pub const Command = struct {
    code: CommandCode,
    data: []u8,
    orders: std.ArrayList(Order),
};
```

Represents a complete 3270 command with orders.

---

#### `Order` (struct)
```zig
pub const Order = struct {
    code: OrderCode,
    address: u16,
    attributes: FieldAttributes,
    data: []u8,
};
```

Represents a 3270 order within a command.

---

#### `Address` (struct)
```zig
pub const Address = struct {
    row: u8,      // 0-23
    col: u8,      // 0-79
};
```

Screen address as row/column pair.

---

### Protocol Functions

#### `Parser.init(allocator, buffer) Parser`
```zig
pub fn init(
    allocator: std.mem.Allocator,
    buffer: []const u8,
) Parser
```

Create parser for buffer.

---

#### `Parser.parse_command() !Command`
```zig
pub fn parse_command(self: *Parser) !Command
```

Parse next 3270 command from buffer.

**Returns**: Parsed Command struct

**Errors**:
- `InvalidCommand` - Unknown command code
- `ParseError` - Malformed data

---

#### `Parser.parse_order() !Order`
```zig
pub fn parse_order(self: *Parser) !Order
```

Parse next 3270 order from buffer.

---

#### `parse_buffer_address(buffer: []const u8, offset: usize) ![2]u8`
```zig
pub fn parse_buffer_address(
    buffer: []const u8,
    offset: usize,
) ![2]u8
```

Decode 2-byte 3270 address to row/col.

**Parameters**:
- `buffer` - Protocol data
- `offset` - Starting position

**Returns**: [row, col]

**Errors**:
- `InvalidAddress` - Malformed address bytes

---

#### `address_to_offset(row, col) u16`
```zig
pub fn address_to_offset(row: u8, col: u8) u16
```

Convert row/col to screen offset.

**Formula**: `offset = row * 80 + col`

---

## Advanced Features API

### Advanced Allocators

**Module**: `advanced_allocators`

#### Types and Functions

```zig
pub const RingBufferAllocator = struct {
    pub fn init(capacity: usize) !RingBufferAllocator { ... }
    pub fn allocate(size: usize) ![]u8 { ... }
    pub fn free(ptr: []u8) void { ... }
    pub fn peek(offset: usize, len: usize) []u8 { ... }
    pub fn available() usize { ... }
    pub fn deinit() void { ... }
};

pub const FixedPoolAllocator = struct {
    pub fn init(block_size: usize, num_blocks: usize) !FixedPoolAllocator { ... }
    pub fn allocate() ![]u8 { ... }
    pub fn free(ptr: []u8) void { ... }
    pub fn is_exhausted() bool { ... }
    pub fn stats() PoolStats { ... }
};

pub const ScratchAllocator = struct {
    pub fn init(chunk_size: usize) !ScratchAllocator { ... }
    pub fn allocate(size: usize) ![]u8 { ... }
    pub fn reset() void { ... }
    pub fn peak_memory() usize { ... }
};
```

Specialized allocators for high-performance scenarios.

---

### Zero-Copy Parsing

**Module**: `zero_copy_parser`

```zig
pub const BufferView = struct {
    pub fn slice(offset: usize, len: usize) BufferView { ... }
    pub fn peek(offset: usize) u8 { ... }
    pub fn remaining() usize { ... }
};

pub const ZeroCopyParser = struct {
    pub fn parse_command() !Command { ... }
    pub fn parse_address() ![2]u8 { ... }
    pub fn extract_text() []u8 { ... }
};
```

Parse protocol data without allocating intermediate buffers.

---

### EBCDIC Encoding

**Module**: `ebcdic`

```zig
pub fn decode_byte(ebcdic_byte: u8) u8 { ... }
pub fn encode_byte(ascii_byte: u8) !u8 { ... }
pub fn decode(ebcdic: []const u8, ascii: []u8) !usize { ... }
pub fn encode(ascii: []const u8, ebcdic: []u8) !usize { ... }
pub fn decode_alloc(allocator: std.mem.Allocator, data: []const u8) ![]u8 { ... }
pub fn encode_alloc(allocator: std.mem.Allocator, data: []const u8) ![]u8 { ... }
```

Bidirectional EBCDIC ↔ ASCII encoding for mainframe text.

---

## Enterprise Features API

### Session Management

**Module**: `session_pool`

```zig
pub const SessionPool = struct {
    pub fn init(allocator, max_size) !SessionPool { ... }
    pub fn create_session(host, port) !u16 { ... }
    pub fn get_session(id: u16) ?Session { ... }
    pub fn list_sessions() []Session { ... }
    pub fn close_session(id: u16) !void { ... }
    pub fn pause_session(id: u16) !void { ... }
    pub fn resume_session(id: u16) !void { ... }
};
```

Manage multiple concurrent mainframe sessions.

---

### Load Balancing

**Module**: `load_balancer`

```zig
pub const LoadBalancer = struct {
    pub const Strategy = enum { RoundRobin, Weighted, LeastConnections };
    
    pub fn init(strategy: Strategy, endpoints: []Endpoint) !LoadBalancer { ... }
    pub fn select_endpoint() !Endpoint { ... }
    pub fn report_success(endpoint: Endpoint) void { ... }
    pub fn report_failure(endpoint: Endpoint) void { ... }
};
```

Distribute load across multiple mainframe endpoints.

---

### Audit Logging

**Module**: `audit_log`

```zig
pub const AuditLog = struct {
    pub const EventType = enum {
        SessionCreated, SessionClosed, CommandExecuted, FieldModified,
        ErrorOccurred, UnauthorizedAccess
    };
    
    pub fn init(allocator) !AuditLog { ... }
    pub fn log_event(event_type: EventType, details: AuditEvent) !void { ... }
    pub fn export_json() ![]u8 { ... }
    pub fn search(filter: AuditFilter) ![]AuditEvent { ... }
};
```

Record and audit all session activities for compliance.

---

### OpenTelemetry Integration

**Module**: `opentelemetry`

```zig
pub const TraceContext = struct {
    pub fn new() TraceContext { ... }
    pub fn trace_id() [16]u8 { ... }
    pub fn span_id() [8]u8 { ... }
};

pub const Tracer = struct {
    pub fn init(allocator, service_name: []const u8) !Tracer { ... }
    pub fn start_span(name: []const u8) !Span { ... }
    pub fn export_otlp(collector_url: []const u8) !void { ... }
};

pub const Meter = struct {
    pub fn counter(name: []const u8) !Counter { ... }
    pub fn gauge(name: []const u8) !Gauge { ... }
    pub fn histogram(name: []const u8) !Histogram { ... }
};
```

Distributed tracing and metrics collection for observability.

---

## Error Handling & Logging

### Error Context

**Module**: `error_context`

```zig
pub const ParseError = struct {
    position: usize,
    code: u16,
    message: []const u8,
    recovery: []const u8,
};

pub const FieldError = struct {
    field_id: u16,
    code: u16,
    message: []const u8,
};

pub const ConnectionError = struct {
    code: u16,
    timeout_ms: u32,
    message: []const u8,
};
```

Structured error types with recovery guidance.

---

### Debug Logging

**Module**: `debug_log`

```zig
pub const LogLevel = enum { Disabled, Error, Warn, Info, Debug, Trace };
pub const Format = enum { Text, Json };

pub fn set_level(module: []const u8, level: LogLevel) void { ... }
pub fn set_format(format: Format) void { ... }
pub fn init_from_env() void { ... }
pub fn log(
    module: []const u8,
    level: LogLevel,
    message: []const u8,
) void { ... }
```

Configurable per-module logging with environment variable support.

---

## C Bindings & Foreign Function Interface

### Module: `c_bindings`

The library exports C-compatible functions for use in C/C++ applications.

```c
// Memory management
void* zig3270_malloc(size_t size);
void zig3270_free(void* ptr);
void zig3270_string_free(char* str);

// EBCDIC encoding/decoding
uint8_t zig3270_ebcdic_decode_byte(uint8_t byte);
uint8_t zig3270_ebcdic_encode_byte(uint8_t byte);
size_t zig3270_ebcdic_decode(const uint8_t* src, size_t src_len,
                             uint8_t* dst, size_t dst_len);
size_t zig3270_ebcdic_encode(const uint8_t* src, size_t src_len,
                             uint8_t* dst, size_t dst_len);

// Client functions (stubs)
void* zig3270_client_new(const char* host, uint16_t port);
void zig3270_client_connect(void* client);
void zig3270_client_disconnect(void* client);
void zig3270_client_free(void* client);

// Screen functions (stubs)
void* zig3270_screen_new();
void zig3270_screen_clear(void* screen);
void zig3270_screen_write(void* screen, uint16_t offset, const char* text);
char* zig3270_screen_to_string(void* screen);
void zig3270_screen_free(void* screen);

// Version information
const char* zig3270_version();
const char* zig3270_protocol_version();
```

See `include/zig3270.h` for complete C header file.

---

## Python Bindings

### Module: `bindings.python.zig3270`

The Python module provides ctypes bindings for cross-language integration.

```python
from zig3270 import TN3270Client, ebcdic_encode, ebcdic_decode
from zig3270 import Address, FieldAttr

# EBCDIC operations
encoded = ebcdic_encode("HELLO")
decoded = ebcdic_decode(encoded)

# Client connection
client = TN3270Client("mainframe.example.com", 23)
try:
    client.connect()
    response = client.read_response()
finally:
    client.disconnect()

# Screen and field operations
address = Address(row=5, col=10)
field = FieldAttr(protected=True, numeric=False)
```

See `bindings/python/zig3270.py` for complete Python wrapper.

---

## Configuration & Validation

### Module: `config_validator`

```zig
pub const ConfigValidator = struct {
    pub fn validate_host(host: []const u8) !void { ... }
    pub fn validate_port(port: u16) !void { ... }
    pub fn validate_log_level(level: []const u8) !void { ... }
    pub fn validate_log_format(format: []const u8) !void { ... }
};
```

Runtime configuration validation with detailed error messages.

---

## Performance Profiling

### Module: `profiler`

```zig
pub const Profiler = struct {
    pub fn init(allocator) !Profiler { ... }
    pub fn start_operation(name: []const u8) u32 { ... }
    pub fn end_operation(id: u32) !void { ... }
    pub fn report() ![]u8 { ... }
};
```

Memory and timing profiling for performance analysis.

---

## Best Practices

### Memory Management

All APIs accept an `allocator` parameter. Use appropriate allocators:
- `std.heap.GeneralPurposeAllocator` for development
- `advanced_allocators.ArenaAllocator` for batch processing
- `advanced_allocators.FixedPoolAllocator` for real-time systems

### Error Handling

Always check error returns:
```zig
try client.connect() catch |err| {
    try debug_log.log("client", .Error, 
                     try std.fmt.allocPrint(allocator, "Connect failed: {}", .{err}));
};
```

### Resource Cleanup

Use `defer` for cleanup:
```zig
var client = try Client.init(allocator, "host", 23);
defer client.disconnect();
```

### Testing

Run tests to validate:
```bash
zig build test
task test
```

---

## Version History

- **v0.11.3**: Complete API reference, enterprise features stabilized
- **v0.11.1**: Advanced allocators, zero-copy parsing, OpenTelemetry
- **v0.11.0**: Language bindings, Windows support
- **v0.9.0**: Session management, load balancing, audit logging
- **v0.7.0**: Core protocol implementation stable

---

## Support & Contributing

For questions or issues:
- GitHub Issues: https://github.com/chunghha/zig-3270/issues
- Documentation: See `docs/` directory
- Examples: See `examples/` directory

