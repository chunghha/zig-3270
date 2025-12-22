# Advanced Integration Guide

Complete guide for embedding zig-3270 as a library with advanced customization options.

## Table of Contents

1. [Custom Allocator Integration](#custom-allocator-integration)
2. [Event Callback Hooks](#event-callback-hooks)
3. [Custom Screen Rendering](#custom-screen-rendering)
4. [Protocol Interceptors](#protocol-interceptors)
5. [Field Validators](#field-validators)
6. [Connection Lifecycle](#connection-lifecycle)
7. [Advanced Examples](#advanced-examples)
8. [Performance Considerations](#performance-considerations)
9. [Error Handling Patterns](#error-handling-patterns)

---

## Custom Allocator Integration

zig-3270 is designed to work with any Zig allocator. This allows you to use custom memory management strategies optimized for your application.

### Using Arena Allocator

```zig
const std = @import("std");
const emulator = @import("zig3270");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // All allocations from emulator will use arena
    var client = try emulator.client.Client.init(allocator, "mainframe.example.com", 23);
    defer client.deinit();

    // ... use client ...
}
```

**Benefits**: Efficient batch deallocation, no fragmentation

### Using Fixed Buffer Allocator

For embedded systems with limited memory:

```zig
pub fn main() !void {
    var buffer: [1024 * 1024]u8 = undefined; // 1MB fixed buffer
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fixed.allocator();

    // Allocations are bounded by 1MB
    var client = try emulator.client.Client.init(allocator, "host", 23);
    // ...
}
```

**Benefits**: Predictable memory usage, real-time safe

### Using Instrumented Allocator

To track memory usage:

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Track allocations with memory monitor
    var monitor = ConnectionMonitor.init(gpa.allocator());
    defer monitor.deinit();

    var client = try emulator.client.Client.init(gpa.allocator(), "host", 23);
    
    // Monitor memory during session
    try monitor.record_bytes_sent("host", 23, 1024);
    
    defer client.deinit();
}
```

---

## Event Callback Hooks

Subscribe to connection and protocol events for custom handling.

### Connection Events

```zig
pub const ConnectionHandler = struct {
    on_connected: ?fn (*ConnectionHandler) void = null,
    on_disconnected: ?fn (*ConnectionHandler) void = null,
    on_error: ?fn (*ConnectionHandler, error_type: u32) void = null,

    pub fn handle_connected(self: *ConnectionHandler) void {
        if (self.on_connected) |cb| {
            cb(self);
        }
    }
};

pub fn main() !void {
    var handler = ConnectionHandler{
        .on_connected = on_connected_callback,
        .on_error = on_error_callback,
    };

    // ... use handler ...
}

fn on_connected_callback(handler: *ConnectionHandler) void {
    std.debug.print("Connection established!\n", .{});
}

fn on_error_callback(handler: *ConnectionHandler, error_type: u32) void {
    std.debug.print("Error occurred: {}\n", .{error_type});
}
```

### Protocol Events

Track protocol-level events:

```zig
pub const ProtocolListener = struct {
    on_command_received: ?fn (command_code: u8) void = null,
    on_field_detected: ?fn (field_count: u32) void = null,
    on_error: ?fn (error_code: u32) void = null,

    pub fn notify_command(self: *ProtocolListener, cmd: u8) void {
        if (self.on_command_received) |cb| {
            cb(cmd);
        }
    }
};
```

---

## Custom Screen Rendering

Implement custom rendering for specialized display requirements.

### Screen Update Handler

```zig
pub const CustomRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn render_screen(self: *CustomRenderer, screen: *Screen) !void {
        // Custom rendering logic
        for (screen.fields.items) |field| {
            try self.render_field(field);
        }
    }

    fn render_field(self: *CustomRenderer, field: *Field) !void {
        // Custom field rendering
        const attributes = field.attributes;
        
        // Apply custom styling based on attributes
        if (attributes.protected) {
            // Render as protected
        }
        if (attributes.hidden) {
            // Don't render visible text
        }
        if (attributes.intense) {
            // Render with emphasis
        }
    }
};
```

### Web-Based Terminal Frontend

```zig
pub const WebTerminal = struct {
    allocator: std.mem.Allocator,
    websocket: *WebSocket,

    pub fn handle_screen_update(self: *WebTerminal, screen: *Screen) !void {
        // Convert screen to JSON for web client
        var json_buffer = try self.allocator.alloc(u8, 4096);
        defer self.allocator.free(json_buffer);

        const json = try std.fmt.bufPrint(json_buffer, 
            \\{{"screen":{{"width":80,"height":24,"fields":[]}}}}
        , .{});

        try self.websocket.send(json);
    }
};
```

---

## Protocol Interceptors

Intercept and modify protocol traffic for monitoring or testing.

### Protocol Snooper

```zig
pub const ProtocolInterceptor = struct {
    allocator: std.mem.Allocator,
    log_file: std.fs.File,

    pub fn init(allocator: std.mem.Allocator, log_path: []const u8) !ProtocolInterceptor {
        const file = try std.fs.cwd().createFile(log_path, .{});
        return .{
            .allocator = allocator,
            .log_file = file,
        };
    }

    pub fn intercept_send(self: *ProtocolInterceptor, data: []const u8) !void {
        const timestamp = std.time.milliTimestamp();
        try self.log_file.writer().print("SEND[{}]: ", .{timestamp});
        try self.log_hex_dump(data);
    }

    pub fn intercept_receive(self: *ProtocolInterceptor, data: []const u8) !void {
        const timestamp = std.time.milliTimestamp();
        try self.log_file.writer().print("RECV[{}]: ", .{timestamp});
        try self.log_hex_dump(data);
    }

    fn log_hex_dump(self: *ProtocolInterceptor, data: []const u8) !void {
        for (data) |byte| {
            try self.log_file.writer().print("{X:0>2} ", .{byte});
        }
        try self.log_file.writer().writeAll("\n");
    }

    pub fn deinit(self: *ProtocolInterceptor) void {
        self.log_file.close();
    }
};
```

---

## Field Validators

Implement custom validation rules for field data.

### Custom Field Validator

```zig
pub const FieldValidator = struct {
    allocator: std.mem.Allocator,
    rules: std.StringHashMap(ValidationRule),

    pub const ValidationRule = struct {
        rule_type: RuleType,
        pattern: []const u8,
        min_length: ?usize = null,
        max_length: ?usize = null,

        pub const RuleType = enum {
            numeric,
            alphanumeric,
            email,
            pattern,
            custom,
        };
    };

    pub fn validate_field(self: *FieldValidator, field_name: []const u8, data: []const u8) !bool {
        if (self.rules.get(field_name)) |rule| {
            return try self.apply_rule(rule, data);
        }
        return true; // No validation rule, accept
    }

    fn apply_rule(self: *FieldValidator, rule: ValidationRule, data: []const u8) !bool {
        // Check length constraints
        if (rule.min_length) |min| {
            if (data.len < min) return false;
        }
        if (rule.max_length) |max| {
            if (data.len > max) return false;
        }

        // Check type-specific validation
        switch (rule.rule_type) {
            .numeric => {
                for (data) |byte| {
                    if (byte < '0' or byte > '9') return false;
                }
            },
            .alphanumeric => {
                for (data) |byte| {
                    if (!std.ascii.isAlphanumeric(byte)) return false;
                }
            },
            else => return true,
        }

        return true;
    }
};
```

---

## Connection Lifecycle

Manage connection state through complete lifecycle.

### Session Manager

```zig
pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(*Session),

    pub const Session = struct {
        id: []const u8,
        client: *Client,
        state: SessionState,
        created_at: i64,
        last_activity: i64,
        metadata: std.StringHashMap([]const u8),

        pub const SessionState = enum {
            connecting,
            connected,
            authenticated,
            active,
            disconnecting,
            disconnected,
            error,
        };

        pub fn get_uptime(self: *Session) i64 {
            return std.time.milliTimestamp() - self.created_at;
        }

        pub fn is_idle(self: *Session, timeout_ms: i64) bool {
            const idle_time = std.time.milliTimestamp() - self.last_activity;
            return idle_time > timeout_ms;
        }
    };

    pub fn create_session(self: *SessionManager, id: []const u8, client: *Client) !*Session {
        const session = try self.allocator.create(Session);
        session.* = .{
            .id = try self.allocator.dupe(u8, id),
            .client = client,
            .state = .connecting,
            .created_at = std.time.milliTimestamp(),
            .last_activity = std.time.milliTimestamp(),
            .metadata = std.StringHashMap([]const u8).init(self.allocator),
        };

        try self.sessions.put(id, session);
        return session;
    }

    pub fn terminate_session(self: *SessionManager, id: []const u8) !void {
        if (self.sessions.fetchRemove(id)) |entry| {
            entry.value.client.disconnect();
            self.allocator.free(entry.value.id);
            entry.value.metadata.deinit();
            self.allocator.destroy(entry.value);
        }
    }
};
```

---

## Advanced Examples

### Example 1: Multi-Connection Manager

```zig
pub const MultiConnectionManager = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(*ManagedConnection),
    monitor: *ConnectionMonitor,

    pub const ManagedConnection = struct {
        client: *Client,
        pool_id: usize,
        health_check_interval_ms: u32 = 5000,
        last_health_check: i64 = 0,

        pub fn needs_health_check(self: *ManagedConnection) bool {
            const now = std.time.milliTimestamp();
            return now - self.last_health_check > self.health_check_interval_ms;
        }
    };

    pub fn add_connection(self: *MultiConnectionManager, client: *Client) !usize {
        const managed = try self.allocator.create(ManagedConnection);
        managed.* = .{
            .client = client,
            .pool_id = self.connections.items.len,
            .last_health_check = std.time.milliTimestamp(),
        };

        try self.connections.append(managed);
        return managed.pool_id;
    }

    pub fn check_all_health(self: *MultiConnectionManager) !void {
        for (self.connections.items) |conn| {
            if (conn.needs_health_check()) {
                const alert = try self.monitor.check_health(
                    conn.client.host,
                    conn.client.port,
                );
                defer alert.deinit(self.allocator);

                conn.last_health_check = std.time.milliTimestamp();
            }
        }
    }
};
```

### Example 2: Batch Command Processor

```zig
pub const BatchProcessor = struct {
    allocator: std.mem.Allocator,
    client: *Client,
    commands: std.ArrayList([]const u8),

    pub fn add_command(self: *BatchProcessor, cmd: []const u8) !void {
        try self.commands.append(try self.allocator.dupe(u8, cmd));
    }

    pub fn execute_batch(self: *BatchProcessor) !BatchResult {
        var result = BatchResult{
            .total_commands = self.commands.items.len,
            .successful = 0,
            .failed = 0,
            .start_time = std.time.milliTimestamp(),
        };

        for (self.commands.items) |cmd| {
            self.client.send(cmd) catch {
                result.failed += 1;
                continue;
            };
            result.successful += 1;
        }

        result.duration_ms = std.time.milliTimestamp() - result.start_time;
        return result;
    }
};

pub const BatchResult = struct {
    total_commands: usize,
    successful: usize,
    failed: usize,
    duration_ms: i64,

    pub fn success_rate(self: BatchResult) f64 {
        if (self.total_commands == 0) return 0;
        return @as(f64, @floatFromInt(self.successful)) / @as(f64, @floatFromInt(self.total_commands));
    }
};
```

### Example 3: Screen History and Diff

```zig
pub const ScreenHistory = struct {
    allocator: std.mem.Allocator,
    snapshots: std.ArrayList(ScreenSnapshot),
    max_history: usize = 100,

    pub const ScreenSnapshot = struct {
        timestamp: i64,
        content: []const u8,
        field_count: u32,
    };

    pub fn capture_screen(self: *ScreenHistory, screen: *Screen) !void {
        const snapshot = ScreenSnapshot{
            .timestamp = std.time.milliTimestamp(),
            .content = try self.allocator.dupe(u8, screen.buffer),
            .field_count = @intCast(screen.fields.items.len),
        };

        try self.snapshots.append(snapshot);

        // Keep history size bounded
        if (self.snapshots.items.len > self.max_history) {
            const removed = self.snapshots.orderedRemove(0);
            self.allocator.free(removed.content);
        }
    }

    pub fn diff_snapshots(self: *ScreenHistory, idx1: usize, idx2: usize) !ScreenDiff {
        if (idx1 >= self.snapshots.items.len or idx2 >= self.snapshots.items.len) {
            return error.InvalidIndex;
        }

        const snap1 = self.snapshots.items[idx1];
        const snap2 = self.snapshots.items[idx2];

        return .{
            .timestamp_diff_ms = snap2.timestamp - snap1.timestamp,
            .field_count_change = @as(i32, @intCast(snap2.field_count)) - @as(i32, @intCast(snap1.field_count)),
            .content_changed = !std.mem.eql(u8, snap1.content, snap2.content),
        };
    }
};

pub const ScreenDiff = struct {
    timestamp_diff_ms: i64,
    field_count_change: i32,
    content_changed: bool,
};
```

---

## Performance Considerations

### Memory Pooling for Batch Operations

```zig
pub fn batch_operation_with_pooling(allocator: std.mem.Allocator, count: u32) !void {
    // Use field storage for bulk field creation
    var storage = try FieldDataStorage.init(allocator, 10000);
    defer storage.deinit();

    for (0..count) |i| {
        const field_data = "Field data...";
        _ = try storage.allocate_field(field_data);
    }

    // All fields share single allocation
}
```

### Lazy Rendering

```zig
pub const LazyRenderer = struct {
    allocator: std.mem.Allocator,
    dirty_regions: std.ArrayList(Rect),
    
    pub const Rect = struct {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    };

    pub fn mark_dirty(self: *LazyRenderer, rect: Rect) !void {
        // Only render changed regions
        try self.dirty_regions.append(rect);
    }

    pub fn render_only_dirty(self: *LazyRenderer, screen: *Screen) !void {
        for (self.dirty_regions.items) |rect| {
            try self.render_region(screen, rect);
        }
        self.dirty_regions.clearRetainingCapacity();
    }
};
```

---

## Error Handling Patterns

### Structured Error Recovery

```zig
pub fn safe_connection_attempt(allocator: std.mem.Allocator, host: []const u8, port: u16) !?*Client {
    var client = Client.init(allocator, host, port) catch |err| {
        std.debug.print("Failed to initialize: {}\n", .{err});
        return null;
    };

    client.connect() catch |err| {
        switch (err) {
            error.ConnectionTimeout => {
                std.debug.print("Connection timed out (>15s)\n", .{});
            },
            error.ConnectionRefused => {
                std.debug.print("Server refused connection on port {}\n", .{port});
            },
            error.NetworkUnreachable => {
                std.debug.print("Network unreachable for host {s}\n", .{host});
            },
            else => {
                std.debug.print("Unknown connection error: {}\n", .{err});
            },
        }
        return null;
    };

    return client;
}
```

### Fault-Tolerant Session

```zig
pub const FaultTolerantSession = struct {
    allocator: std.mem.Allocator,
    client: *Client,
    recovery: *ErrorRecovery,
    max_retries: u32 = 3,

    pub fn send_command_with_recovery(self: *FaultTolerantSession, cmd: []const u8) !bool {
        var retry_count: u32 = 0;

        while (retry_count < self.max_retries) {
            self.client.send(cmd) catch |err| {
                retry_count += 1;
                if (retry_count >= self.max_retries) {
                    return false;
                }
                std.posix.nanosleep(0, 1_000_000_000); // 1 second
                continue;
            };
            return true;
        }

        return false;
    }
};
```

---

## Resources

- **API Reference**: See root.zig for complete type definitions
- **Configuration**: See docs/CONFIG_REFERENCE.md
- **Deployment**: See docs/DEPLOYMENT.md
- **Examples**: See examples/ directory

---

**Last Updated**: December 24, 2024  
**Version**: v0.8.0  
**Maintainer**: zig-3270 Development Team
