const std = @import("std");
const protocol = @import("protocol.zig");
const command_mod = @import("command.zig");

/// Protocol event that was captured
pub const ProtocolEvent = struct {
    timestamp: i64,
    sequence_number: u64,
    event_type: EventType,
    data: []const u8,

    pub fn deinit(self: *ProtocolEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub const EventType = enum {
    command_sent,
    response_received,
};

/// Statistics about captured protocol data
pub const ProtocolAnalysis = struct {
    command_count: usize = 0,
    response_count: usize = 0,
    data_sent_bytes: u64 = 0,
    data_received_bytes: u64 = 0,
    field_updates: usize = 0,
    keyboard_events: usize = 0,
    earliest_timestamp: i64 = 0,
    latest_timestamp: i64 = 0,

    pub fn duration_ms(self: ProtocolAnalysis) i64 {
        if (self.latest_timestamp <= self.earliest_timestamp) return 0;
        return self.latest_timestamp - self.earliest_timestamp;
    }
};

/// Snoops on protocol traffic and captures events
pub const ProtocolSnooper = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(ProtocolEvent),
    sequence_counter: u64 = 0,
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) ProtocolSnooper {
        return ProtocolSnooper{
            .allocator = allocator,
            .events = std.ArrayList(ProtocolEvent).init(allocator),
        };
    }

    pub fn deinit(self: *ProtocolSnooper) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
    }

    /// Capture an outgoing command
    pub fn capture_command(self: *ProtocolSnooper, data: []const u8) !void {
        if (!self.enabled) return;

        const timestamp = std.time.milliTimestamp();
        const event = ProtocolEvent{
            .timestamp = timestamp,
            .sequence_number = self.sequence_counter,
            .event_type = .command_sent,
            .data = try self.allocator.dupe(u8, data),
        };

        try self.events.append(event);
        self.sequence_counter += 1;
    }

    /// Capture an incoming response
    pub fn capture_response(self: *ProtocolSnooper, data: []const u8) !void {
        if (!self.enabled) return;

        const timestamp = std.time.milliTimestamp();
        const event = ProtocolEvent{
            .timestamp = timestamp,
            .sequence_number = self.sequence_counter,
            .event_type = .response_received,
            .data = try self.allocator.dupe(u8, data),
        };

        try self.events.append(event);
        self.sequence_counter += 1;
    }

    /// Analyze captured events and produce statistics
    pub fn analyze_commands(self: *ProtocolSnooper) ProtocolAnalysis {
        var analysis = ProtocolAnalysis{};

        if (self.events.items.len == 0) return analysis;

        // Initialize timestamps from first event
        analysis.earliest_timestamp = self.events.items[0].timestamp;
        analysis.latest_timestamp = self.events.items[0].timestamp;

        for (self.events.items) |event| {
            switch (event.event_type) {
                .command_sent => {
                    analysis.command_count += 1;
                    analysis.data_sent_bytes += event.data.len;
                },
                .response_received => {
                    analysis.response_count += 1;
                    analysis.data_received_bytes += event.data.len;
                },
            }

            // Update time range
            if (event.timestamp < analysis.earliest_timestamp) {
                analysis.earliest_timestamp = event.timestamp;
            }
            if (event.timestamp > analysis.latest_timestamp) {
                analysis.latest_timestamp = event.timestamp;
            }
        }

        return analysis;
    }

    /// Export captured log to file
    pub fn export_log(self: *ProtocolSnooper, path: []const u8) !void {
        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var writer = file.writer();

        // Write header
        try writer.print("=== PROTOCOL SNOOPER LOG ===\n", .{});
        try writer.print("Total Events: {}\n", .{self.events.items.len});
        try writer.print("\n", .{});

        // Write each event
        for (self.events.items) |event| {
            const event_type_str = switch (event.event_type) {
                .command_sent => "COMMAND_SENT",
                .response_received => "RESPONSE_RECEIVED",
            };

            try writer.print("[{:04}] {s} at {} ms, {} bytes\n", .{
                event.sequence_number,
                event_type_str,
                event.timestamp,
                event.data.len,
            });

            // Print hex dump of data
            try writer.print("      HEX: ", .{});
            for (event.data, 0..) |byte, i| {
                if (i > 0 and i % 16 == 0) {
                    try writer.print("\n           ", .{});
                }
                try writer.print("{x:02} ", .{byte});
            }
            try writer.print("\n", .{});

            // Print ASCII dump
            try writer.print("      ASCII: ", .{});
            for (event.data) |byte| {
                if (byte >= 32 and byte < 127) {
                    try writer.print("{c}", .{@as(u8, byte)});
                } else {
                    try writer.print(".", .{});
                }
            }
            try writer.print("\n\n", .{});
        }

        // Write analysis
        const analysis = self.analyze_commands();
        try writer.print("=== ANALYSIS ===\n", .{});
        try writer.print("Commands Sent: {}\n", .{analysis.command_count});
        try writer.print("Responses Received: {}\n", .{analysis.response_count});
        try writer.print("Bytes Sent: {}\n", .{analysis.data_sent_bytes});
        try writer.print("Bytes Received: {}\n", .{analysis.data_received_bytes});
        try writer.print("Duration: {} ms\n", .{analysis.duration_ms()});
    }

    /// Clear all captured events
    pub fn clear(self: *ProtocolSnooper) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.clearRetainingCapacity();
        self.sequence_counter = 0;
    }

    /// Enable/disable snooping
    pub fn set_enabled(self: *ProtocolSnooper, enabled: bool) void {
        self.enabled = enabled;
    }
};

// Tests
test "protocol snooper: capture command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    const cmd_data = [_]u8{ 0x05, 0x11, 0x00, 0x00, 0x1D, 0x00 };
    try snooper.capture_command(&cmd_data);

    try std.testing.expectEqual(@as(usize, 1), snooper.events.items.len);
    try std.testing.expectEqual(EventType.command_sent, snooper.events.items[0].event_type);
    try std.testing.expectEqual(@as(u64, 0), snooper.events.items[0].sequence_number);
}

test "protocol snooper: capture response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    const resp_data = [_]u8{ 0x88, 0x00, 0x00 };
    try snooper.capture_response(&resp_data);

    try std.testing.expectEqual(@as(usize, 1), snooper.events.items.len);
    try std.testing.expectEqual(EventType.response_received, snooper.events.items[0].event_type);
}

test "protocol snooper: alternating commands and responses" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    const cmd_data = [_]u8{ 0x05, 0x11, 0x00, 0x00 };
    const resp_data = [_]u8{ 0x88, 0x00, 0x00 };

    try snooper.capture_command(&cmd_data);
    try snooper.capture_response(&resp_data);
    try snooper.capture_command(&cmd_data);

    try std.testing.expectEqual(@as(usize, 3), snooper.events.items.len);
    try std.testing.expectEqual(EventType.command_sent, snooper.events.items[0].event_type);
    try std.testing.expectEqual(EventType.response_received, snooper.events.items[1].event_type);
    try std.testing.expectEqual(EventType.command_sent, snooper.events.items[2].event_type);
    try std.testing.expectEqual(@as(u64, 2), snooper.events.items[2].sequence_number);
}

test "protocol snooper: analyze commands" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    const cmd_data = [_]u8{ 0x05, 0x11, 0x00, 0x00 };
    const resp_data = [_]u8{ 0x88, 0x00, 0x00, 0x00, 0x00 };

    try snooper.capture_command(&cmd_data);
    try snooper.capture_response(&resp_data);
    try snooper.capture_command(&cmd_data);

    const analysis = snooper.analyze_commands();

    try std.testing.expectEqual(@as(usize, 2), analysis.command_count);
    try std.testing.expectEqual(@as(usize, 1), analysis.response_count);
    try std.testing.expectEqual(@as(u64, 8), analysis.data_sent_bytes); // 2 commands * 4 bytes
    try std.testing.expectEqual(@as(u64, 5), analysis.data_received_bytes); // 1 response * 5 bytes
}

test "protocol snooper: disable snooping" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    snooper.set_enabled(false);

    const cmd_data = [_]u8{ 0x05, 0x11, 0x00, 0x00 };
    try snooper.capture_command(&cmd_data);

    try std.testing.expectEqual(@as(usize, 0), snooper.events.items.len);
}

test "protocol snooper: clear events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snooper = ProtocolSnooper.init(allocator);
    defer snooper.deinit();

    const cmd_data = [_]u8{ 0x05, 0x11, 0x00, 0x00 };
    try snooper.capture_command(&cmd_data);
    try snooper.capture_command(&cmd_data);

    try std.testing.expectEqual(@as(usize, 2), snooper.events.items.len);

    snooper.clear();

    try std.testing.expectEqual(@as(usize, 0), snooper.events.items.len);
    try std.testing.expectEqual(@as(u64, 0), snooper.sequence_counter);
}
