const std = @import("std");
const protocol = @import("protocol.zig");
const parser = @import("parser.zig");
const stream_parser = @import("stream_parser.zig");
const command = @import("command.zig");
const data_entry = @import("data_entry.zig");

/// Protocol layer facade
/// Consolidates: protocol.zig, parser.zig, stream_parser.zig, command.zig, data_entry.zig
/// Provides unified interface for parsing inbound TN3270 data and formatting outbound responses

// Re-export protocol types for public API
pub const CommandCode = protocol.CommandCode;
pub const OrderCode = protocol.OrderCode;
pub const FieldAttribute = protocol.FieldAttribute;
pub const Address = protocol.Address;

// Re-export parser types
pub const Parser = parser.Parser;
pub const Command = command.Command;
pub const Order = command.Order;
pub const CommandParser = command.CommandParser;
pub const StreamParser = stream_parser.StreamParser;

// Data entry type
pub const DataEntry = data_entry.DataEntry;

/// Parse inbound 3270 data stream
/// Handles: command code + order parsing
pub const ParsedCommand = struct {
    code: CommandCode,
    orders: std.ArrayList(Order),

    pub fn deinit(self: *ParsedCommand, allocator: std.mem.Allocator) void {
        for (self.orders.items) |*order| {
            order.deinit(allocator);
        }
        self.orders.deinit();
    }
};

/// Format outbound 3270 response
/// Handles: AID + field data encoding
pub const FormattedResponse = struct {
    bytes: []u8,

    pub fn deinit(self: *FormattedResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

test "protocol layer imports" {
    // Verify all protocol types are accessible
    _ = CommandCode;
    _ = OrderCode;
    _ = FieldAttribute;
    _ = Address;
    _ = Parser;
    _ = Command;
    _ = Order;
    _ = CommandParser;
    _ = StreamParser;
    _ = DataEntry;
}

test "protocol layer parse command basic" {
    var buffer: [5]u8 = .{ @intFromEnum(CommandCode.write), 0x11, 0x00, 0x00, 0x42 };
    var parser_inst = Parser.init(std.testing.allocator, &buffer);

    const code_byte = try parser_inst.read();
    const code: CommandCode = std.meta.intToEnum(CommandCode, code_byte) catch return error.InvalidCode;

    try std.testing.expectEqual(CommandCode.write, code);
    try std.testing.expectEqual(@as(usize, 1), parser_inst.position);
}

test "protocol layer command parser" {
    const allocator = std.testing.allocator;
    const buffer = &.{ @intFromEnum(CommandCode.write), 0x42, 0x43 };

    var cmd_parser = CommandParser.init(allocator);
    const cmd = try cmd_parser.parse_command(buffer);

    try std.testing.expect(cmd != null);
    if (cmd) |c| {
        try std.testing.expectEqual(CommandCode.write, c.code);
        var cmd_copy = c;
        cmd_copy.deinit(allocator);
    }
}

test "protocol layer stream parser basic" {
    var buffer: [3]u8 = .{ @intFromEnum(CommandCode.read_modified), 0x42, 0x43 };
    var sp = StreamParser.init(std.testing.allocator, &buffer);

    const cmd = try sp.next_command();
    try std.testing.expect(cmd != null);
    if (cmd) |c| {
        try std.testing.expectEqual(CommandCode.read_modified, c.code);
        var cmd_copy = c;
        cmd_copy.deinit(std.testing.allocator);
    }
}
