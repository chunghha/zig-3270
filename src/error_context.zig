const std = @import("std");

/// Error context module for enhanced error reporting
/// Provides structured error information with context and recovery suggestions
pub const ErrorContext = struct {
    /// Error code enumeration for better error classification
    pub const ErrorCode = enum(u16) {
        // Parse errors (0x1000-0x1fff)
        parse_end_of_buffer = 0x1001,
        parse_insufficient_data = 0x1002,
        parse_invalid_code = 0x1003,
        parse_invalid_opcode = 0x1004,
        parse_malformed_command = 0x1005,

        // Field errors (0x2000-0x2fff)
        field_protected = 0x2001,
        field_full = 0x2002,
        field_out_of_bounds = 0x2003,
        field_no_unprotected = 0x2004,
        field_no_current = 0x2005,
        field_invalid_index = 0x2006,
        field_validation_failed = 0x2007,
        field_overlapping = 0x2008,

        // Connection errors (0x3000-0x3fff)
        conn_not_connected = 0x3001,
        conn_invalid_address = 0x3002,
        conn_refused = 0x3003,
        conn_timeout = 0x3004,
        conn_closed = 0x3005,
        conn_io_error = 0x3006,

        // Configuration errors (0x4000-0x4fff)
        config_invalid_value = 0x4001,
        config_missing_required = 0x4002,
        config_conflicting_settings = 0x4003,
        config_file_error = 0x4004,

        pub fn description(self: ErrorCode) []const u8 {
            return switch (self) {
                .parse_end_of_buffer => "Unexpected end of buffer",
                .parse_insufficient_data => "Insufficient data",
                .parse_invalid_code => "Invalid code byte",
                .parse_invalid_opcode => "Invalid opcode",
                .parse_malformed_command => "Malformed command",
                .field_protected => "Protected field modification",
                .field_full => "Field capacity exceeded",
                .field_out_of_bounds => "Field position out of bounds",
                .field_no_unprotected => "No unprotected fields available",
                .field_no_current => "No current field selected",
                .field_invalid_index => "Invalid field index",
                .field_validation_failed => "Field validation failed",
                .field_overlapping => "Overlapping field definitions",
                .conn_not_connected => "Not connected",
                .conn_invalid_address => "Invalid address",
                .conn_refused => "Connection refused",
                .conn_timeout => "Connection timeout",
                .conn_closed => "Connection closed",
                .conn_io_error => "I/O error",
                .config_invalid_value => "Invalid configuration value",
                .config_missing_required => "Missing required configuration",
                .config_conflicting_settings => "Conflicting settings",
                .config_file_error => "Configuration file error",
            };
        }
    };

    /// Error types with context information
    pub const ParseError = struct {
        kind: ParseErrorKind,
        code: ErrorCode = .parse_invalid_code,
        position: usize = 0,
        buffer_size: usize = 0,
        expected: ?[]const u8 = null,
        context: ?[]const u8 = null,

        pub fn message(self: ParseError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .end_of_buffer => blk: {
                    if (self.expected) |exp| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} at position {d}/{d}. Expected: {s}. Recovery: Check buffer size or add error recovery.",
                            .{ self.code, self.code.description(), self.position, self.buffer_size, exp },
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} at position {d}/{d}. Recovery: Ensure complete protocol message.",
                            .{ self.code, self.code.description(), self.position, self.buffer_size },
                        );
                    }
                },
                .insufficient_data => blk: {
                    break :blk std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s} at position {d}/{d}. Recovery: Wait for more data or increase buffer.",
                        .{ self.code, self.code.description(), self.position, self.buffer_size },
                    );
                },
                .invalid_code => blk: {
                    break :blk std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s} at position {d}: 0x{X:0>2}. Recovery: Check protocol specification or verify byte alignment.",
                        .{ self.code, self.code.description(), self.position, self.buffer_size },
                    );
                },
            };
        }

        pub fn deinit(message_str: []u8, allocator: std.mem.Allocator) void {
            allocator.free(message_str);
        }
    };

    pub const ParseErrorKind = enum {
        end_of_buffer,
        insufficient_data,
        invalid_code,
    };

    /// Field-related errors with context
    pub const FieldError = struct {
        kind: FieldErrorKind,
        code: ErrorCode = .field_invalid_index,
        field_index: ?usize = null,
        field_id: ?u8 = null,
        position: ?usize = null,
        attributes: ?[]const u8 = null,

        pub fn message(self: FieldError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .protected => blk: {
                    if (self.field_index) |idx| {
                        if (self.attributes) |attr| {
                            break :blk std.fmt.allocPrint(
                                allocator,
                                "[{d:#x}] {s} field {d} (attrs: {s}). Recovery: Check field attributes via screen inspection or modify unprotected fields.",
                                .{ self.code, self.code.description(), idx, attr },
                            );
                        }
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} field {d}. Recovery: Check field attributes or request different field.",
                            .{ self.code, self.code.description(), idx },
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Check field attributes or request different field.",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
                .full => blk: {
                    if (self.field_index) |idx| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} field {d}. Recovery: Clear field contents or move to next field.",
                            .{ self.code, self.code.description(), idx },
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Clear field contents or move to next field.",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
                .out_of_bounds => blk: {
                    if (self.position) |pos| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} at position {d} (max 1919). Recovery: Verify position calculation for 24x80 grid.",
                            .{ self.code, self.code.description(), pos },
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Verify position is within 0-1919 bounds.",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
                .no_unprotected_fields => {
                    return std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s}. Recovery: Check screen layout or modify form design to include unprotected fields.",
                        .{ self.code, self.code.description() },
                    );
                },
                .no_current_field => {
                    return std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s}. Recovery: Use Tab or arrow keys to navigate to a field first.",
                        .{ self.code, self.code.description() },
                    );
                },
                .invalid_field_index => {
                    if (self.field_index) |idx| {
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} {d}. Recovery: Ensure index is within valid range.",
                            .{ self.code, self.code.description(), idx },
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Verify field index is within bounds.",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
            };
        }

        pub fn deinit(message_str: []u8, allocator: std.mem.Allocator) void {
            allocator.free(message_str);
        }
    };

    pub const FieldErrorKind = enum {
        protected,
        full,
        out_of_bounds,
        no_unprotected_fields,
        no_current_field,
        invalid_field_index,
    };

    /// Client/Connection errors with context
    pub const ConnectionError = struct {
        kind: ConnectionErrorKind,
        code: ErrorCode = .conn_invalid_address,
        host: ?[]const u8 = null,
        port: ?u16 = null,
        timeout_ms: ?u32 = null,

        pub fn message(self: ConnectionError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .not_connected => {
                    return std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s}. Recovery: Establish connection before sending commands.",
                        .{ self.code, self.code.description() },
                    );
                },
                .invalid_address => {
                    if (self.host) |h| {
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}: {s}. Recovery: Use valid host (FQDN or IP) with port like 'mainframe.example.com:3270'.",
                            .{ self.code, self.code.description(), h },
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Use format 'host:port' (e.g., 'server.example.com:3270').",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
                .connection_refused => {
                    if (self.host) |h| {
                        if (self.port) |p| {
                            return std.fmt.allocPrint(
                                allocator,
                                "[{d:#x}] {s} to {s}:{d}. Recovery: Verify server is running, check firewall rules, and confirm port is open.",
                                .{ self.code, self.code.description(), h, p },
                            );
                        }
                    }
                    return std.fmt.allocPrint(
                        allocator,
                        "[{d:#x}] {s}. Recovery: Verify server is running and accepting connections.",
                        .{ self.code, self.code.description() },
                    );
                },
                .timeout => {
                    if (self.host) |h| {
                        if (self.timeout_ms) |ms| {
                            return std.fmt.allocPrint(
                                allocator,
                                "[{d:#x}] {s} to {s} after {d}ms. Recovery: Check network connectivity, try increasing timeout, or contact network administrator.",
                                .{ self.code, self.code.description(), h, ms },
                            );
                        }
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s} to {s}. Recovery: Check network connectivity or increase timeout.",
                            .{ self.code, self.code.description(), h },
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "[{d:#x}] {s}. Recovery: Check network connectivity or increase timeout.",
                            .{ self.code, self.code.description() },
                        );
                    }
                },
            };
        }

        pub fn deinit(message_str: []u8, allocator: std.mem.Allocator) void {
            allocator.free(message_str);
        }
    };

    pub const ConnectionErrorKind = enum {
        not_connected,
        invalid_address,
        connection_refused,
        timeout,
    };
};

// === Tests ===

test "error context parse error end of buffer message" {
    const err = ErrorContext.ParseError{
        .kind = .end_of_buffer,
        .code = .parse_end_of_buffer,
        .position = 5,
        .buffer_size = 10,
        .expected = "command code",
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "position 5"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "command code"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context parse error insufficient data" {
    const err = ErrorContext.ParseError{
        .kind = .insufficient_data,
        .code = .parse_insufficient_data,
        .position = 8,
        .buffer_size = 16,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "position 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context field error protected" {
    const err = ErrorContext.FieldError{
        .kind = .protected,
        .code = .field_protected,
        .field_index = 3,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "field 3"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "protected"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context field error full" {
    const err = ErrorContext.FieldError{
        .kind = .full,
        .code = .field_full,
        .field_index = 1,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "field 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context field error out of bounds" {
    const err = ErrorContext.FieldError{
        .kind = .out_of_bounds,
        .code = .field_out_of_bounds,
        .position = 1920,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "1920"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context connection error not connected" {
    const err = ErrorContext.ConnectionError{
        .kind = .not_connected,
        .code = .conn_not_connected,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Not connected"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context connection error refused" {
    const err = ErrorContext.ConnectionError{
        .kind = .connection_refused,
        .code = .conn_refused,
        .host = "localhost",
        .port = 3270,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "localhost"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "3270"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
}

test "error context all parse error kinds have messages" {
    const errors = [_]ErrorContext.ParseError{
        .{ .kind = .end_of_buffer, .code = .parse_end_of_buffer, .position = 0, .buffer_size = 10 },
        .{ .kind = .insufficient_data, .code = .parse_insufficient_data, .position = 5, .buffer_size = 10 },
        .{ .kind = .invalid_code, .code = .parse_invalid_code, .position = 2, .buffer_size = 10 },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
    }
}

test "error context all field error kinds have messages" {
    const errors = [_]ErrorContext.FieldError{
        .{ .kind = .protected, .code = .field_protected },
        .{ .kind = .full, .code = .field_full },
        .{ .kind = .out_of_bounds, .code = .field_out_of_bounds },
        .{ .kind = .no_unprotected_fields, .code = .field_no_unprotected },
        .{ .kind = .no_current_field, .code = .field_no_current },
        .{ .kind = .invalid_field_index, .code = .field_invalid_index },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
    }
}

test "error context all connection error kinds have messages" {
    const errors = [_]ErrorContext.ConnectionError{
        .{ .kind = .not_connected, .code = .conn_not_connected },
        .{ .kind = .invalid_address, .code = .conn_invalid_address },
        .{ .kind = .connection_refused, .code = .conn_refused },
        .{ .kind = .timeout, .code = .conn_timeout },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Recovery"));
    }
}
