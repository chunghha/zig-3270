const std = @import("std");
const parser = @import("parser.zig");
const command = @import("command.zig");
const protocol = @import("protocol.zig");

/// Parses 3270 data streams
pub const StreamParser = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    command_parser: command.CommandParser,

    pub fn init(allocator: std.mem.Allocator, buffer: []u8) StreamParser {
        return StreamParser{
            .allocator = allocator,
            .parser = parser.Parser.init(allocator, buffer),
            .command_parser = command.CommandParser.init(allocator),
        };
    }

    /// Parse next command from stream
    pub fn next_command(self: *StreamParser) !?command.Command {
        if (!self.parser.has_more()) {
            return null;
        }

        const cmd_byte = try self.parser.read();
        const remaining = self.parser.buffer[self.parser.position..];

        const buffer_with_code = try self.allocator.alloc(u8, remaining.len + 1);
        defer self.allocator.free(buffer_with_code);

        buffer_with_code[0] = cmd_byte;
        @memcpy(buffer_with_code[1..], remaining);

        return try self.command_parser.parse_command(buffer_with_code);
    }

    /// Parse orders from command data
    pub fn parse_orders(self: *StreamParser, data: []const u8) !std.ArrayList(command.Order) {
        return try self.command_parser.parse_orders(data);
    }
};

test "stream parser initialization" {
    var buffer: [10]u8 = undefined;
    const sp = StreamParser.init(std.testing.allocator, &buffer);
    try std.testing.expectEqual(@as(usize, 0), sp.parser.position);
}

test "stream parser next command" {
    var buffer: [3]u8 = .{ @intFromEnum(protocol.CommandCode.write), 0x42, 0x43 };
    var sp = StreamParser.init(std.testing.allocator, &buffer);

    const cmd = try sp.next_command();
    try std.testing.expect(cmd != null);
    if (cmd) |c| {
        try std.testing.expectEqual(protocol.CommandCode.write, c.code);
        var cmd_copy = c;
        cmd_copy.deinit(std.testing.allocator);
    }
}

test "stream parser no more commands" {
    var buffer: [1]u8 = .{@intFromEnum(protocol.CommandCode.write)};
    var sp = StreamParser.init(std.testing.allocator, &buffer);

    _ = try sp.next_command();
    const second = try sp.next_command();
    try std.testing.expectEqual(@as(?command.Command, null), second);
}

test "stream parser parse orders from command data" {
    var buffer: [5]u8 = undefined;
    var sp = StreamParser.init(std.testing.allocator, &buffer);

    const order_data = &.{
        @intFromEnum(protocol.OrderCode.set_buffer_address), 0x00, 0x00,
    };
    var orders = try sp.parse_orders(order_data);
    defer {
        for (orders.items) |*ord| {
            ord.deinit(std.testing.allocator);
        }
        orders.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), orders.items.len);
}
