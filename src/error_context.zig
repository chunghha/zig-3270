const std = @import("std");

/// Error context module for enhanced error reporting
/// Provides structured error information with context and recovery suggestions
pub const ErrorContext = struct {
    /// Error types with context information
    pub const ParseError = struct {
        kind: ParseErrorKind,
        position: usize = 0,
        buffer_size: usize = 0,
        expected: ?[]const u8 = null,

        pub fn message(self: ParseError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .end_of_buffer => blk: {
                    if (self.expected) |exp| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Unexpected end of buffer at position {d}/{d}. Expected: {s}. Suggestion: Check buffer size or add error recovery.",
                            .{ self.position, self.buffer_size, exp },
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Unexpected end of buffer at position {d}/{d}. Suggestion: Ensure complete protocol message.",
                            .{ self.position, self.buffer_size },
                        );
                    }
                },
                .insufficient_data => blk: {
                    break :blk std.fmt.allocPrint(
                        allocator,
                        "Insufficient data at position {d}/{d}. Suggestion: Wait for more data or increase buffer.",
                        .{ self.position, self.buffer_size },
                    );
                },
                .invalid_code => blk: {
                    break :blk std.fmt.allocPrint(
                        allocator,
                        "Invalid code byte at position {d}: 0x{X:0>2}. Suggestion: Check protocol specification or verify byte alignment.",
                        .{ self.position, self.buffer_size },
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
        field_index: ?usize = null,
        position: ?usize = null,

        pub fn message(self: FieldError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .protected => blk: {
                    if (self.field_index) |idx| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Cannot modify protected field {d}. Suggestion: Check field attributes or request different field.",
                            .{idx},
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Cannot modify protected field. Suggestion: Check field attributes or request different field.",
                            .{},
                        );
                    }
                },
                .full => blk: {
                    if (self.field_index) |idx| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Field {d} is full and cannot accept more input. Suggestion: Clear field or move to next field.",
                            .{idx},
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Field is full and cannot accept more input. Suggestion: Clear field or move to next field.",
                            .{},
                        );
                    }
                },
                .out_of_bounds => blk: {
                    if (self.position) |pos| {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Position {d} is out of bounds. Suggestion: Check position calculation or screen dimensions.",
                            .{pos},
                        );
                    } else {
                        break :blk std.fmt.allocPrint(
                            allocator,
                            "Position is out of bounds. Suggestion: Check position calculation or screen dimensions.",
                            .{},
                        );
                    }
                },
                .no_unprotected_fields => {
                    return std.fmt.allocPrint(
                        allocator,
                        "No unprotected fields available on screen. Suggestion: Check field definitions or screen layout.",
                        .{},
                    );
                },
                .no_current_field => {
                    return std.fmt.allocPrint(
                        allocator,
                        "No current field selected. Suggestion: Navigate to a field first or check field state.",
                        .{},
                    );
                },
                .invalid_field_index => {
                    if (self.field_index) |idx| {
                        return std.fmt.allocPrint(
                            allocator,
                            "Invalid field index {d}. Suggestion: Verify field index is within bounds.",
                            .{idx},
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "Invalid field index. Suggestion: Verify field index is within bounds.",
                            .{},
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
        host: ?[]const u8 = null,
        port: ?u16 = null,

        pub fn message(self: ConnectionError, allocator: std.mem.Allocator) ![]u8 {
            return switch (self.kind) {
                .not_connected => {
                    return std.fmt.allocPrint(
                        allocator,
                        "Not connected to server. Suggestion: Call connect() first or check connection status.",
                        .{},
                    );
                },
                .invalid_address => {
                    if (self.host) |h| {
                        return std.fmt.allocPrint(
                            allocator,
                            "Invalid address: {s}. Suggestion: Check host format or verify DNS resolution.",
                            .{h},
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "Invalid address format. Suggestion: Use format 'host:port' or 'IPv4:port'.",
                            .{},
                        );
                    }
                },
                .connection_refused => {
                    if (self.host) |h| {
                        if (self.port) |p| {
                            return std.fmt.allocPrint(
                                allocator,
                                "Connection refused to {s}:{d}. Suggestion: Check if server is running and accepting connections.",
                                .{ h, p },
                            );
                        }
                    }
                    return std.fmt.allocPrint(
                        allocator,
                        "Connection refused. Suggestion: Check if server is running and accepting connections.",
                        .{},
                    );
                },
                .timeout => {
                    if (self.host) |h| {
                        return std.fmt.allocPrint(
                            allocator,
                            "Connection timeout to {s}. Suggestion: Check network connectivity or increase timeout.",
                            .{h},
                        );
                    } else {
                        return std.fmt.allocPrint(
                            allocator,
                            "Connection timeout. Suggestion: Check network connectivity or increase timeout.",
                            .{},
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
        .position = 5,
        .buffer_size = 10,
        .expected = "command code",
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "position 5"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "command code"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
}

test "error context parse error insufficient data" {
    const err = ErrorContext.ParseError{
        .kind = .insufficient_data,
        .position = 8,
        .buffer_size = 16,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "position 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
}

test "error context field error protected" {
    const err = ErrorContext.FieldError{
        .kind = .protected,
        .field_index = 3,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "field 3"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "protected"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
}

test "error context field error full" {
    const err = ErrorContext.FieldError{
        .kind = .full,
        .field_index = 1,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "full"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
}

test "error context field error out of bounds" {
    const err = ErrorContext.FieldError{
        .kind = .out_of_bounds,
        .position = 1920,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "1920"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "bounds"));
}

test "error context connection error not connected" {
    const err = ErrorContext.ConnectionError{
        .kind = .not_connected,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "connected"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
}

test "error context connection error refused" {
    const err = ErrorContext.ConnectionError{
        .kind = .connection_refused,
        .host = "localhost",
        .port = 3270,
    };
    const msg = try err.message(std.testing.allocator);
    defer err.deinit(msg, std.testing.allocator);
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "localhost"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "3270"));
    try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "refused"));
}

test "error context all parse error kinds have messages" {
    const errors = [_]ErrorContext.ParseError{
        .{ .kind = .end_of_buffer, .position = 0, .buffer_size = 10 },
        .{ .kind = .insufficient_data, .position = 5, .buffer_size = 10 },
        .{ .kind = .invalid_code, .position = 2, .buffer_size = 10 },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
    }
}

test "error context all field error kinds have messages" {
    const errors = [_]ErrorContext.FieldError{
        .{ .kind = .protected },
        .{ .kind = .full },
        .{ .kind = .out_of_bounds },
        .{ .kind = .no_unprotected_fields },
        .{ .kind = .no_current_field },
        .{ .kind = .invalid_field_index },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
    }
}

test "error context all connection error kinds have messages" {
    const errors = [_]ErrorContext.ConnectionError{
        .{ .kind = .not_connected },
        .{ .kind = .invalid_address },
        .{ .kind = .connection_refused },
        .{ .kind = .timeout },
    };

    for (errors) |err| {
        const msg = try err.message(std.testing.allocator);
        defer err.deinit(msg, std.testing.allocator);
        try std.testing.expect(msg.len > 0);
        try std.testing.expect(std.mem.containsAtLeast(u8, msg, 1, "Suggestion"));
    }
}
