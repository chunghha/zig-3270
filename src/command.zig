const std = @import("std");
const protocol = @import("protocol.zig");
const parse_utils = @import("parse_utils.zig");

/// Parsed 3270 command
pub const Command = struct {
    code: protocol.CommandCode,
    data: []u8,

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Parsed 3270 order within a command
pub const Order = struct {
    code: protocol.OrderCode,
    data: []u8,

    pub fn deinit(self: *Order, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Command parser
pub const CommandParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandParser {
        return CommandParser{
            .allocator = allocator,
        };
    }

    /// Parse a single command from buffer
    /// Expects: [command_code][command_data...]
    pub fn parse_command(self: *CommandParser, buffer: []const u8) !?Command {
        if (buffer.len == 0) {
            return null;
        }

        const code_byte = buffer[0];
        const code = parse_utils.parse_command_code(code_byte) catch {
            return error.InvalidCommandCode;
        };

        // Command data is everything after the command code
        const data = if (buffer.len > 1)
            try self.allocator.dupe(u8, buffer[1..])
        else
            try self.allocator.alloc(u8, 0);

        return Command{
            .code = code,
            .data = data,
        };
    }

    /// Parse all orders from command data
    pub fn parse_orders(self: *CommandParser, buffer: []const u8) !std.ArrayList(Order) {
        var orders = std.ArrayList(Order).initCapacity(self.allocator, 0) catch std.ArrayList(Order){
            .items = &.{},
            .capacity = 0,
        };

        var pos: usize = 0;
        while (pos < buffer.len) {
            const code_byte = buffer[pos];
            const code = parse_utils.parse_order_code(code_byte) catch {
                pos += 1;
                continue;
            };

            pos += 1;

            // Each order type has different data length
            const order_data = switch (code) {
                .set_buffer_address => blk: {
                    if (pos + 2 > buffer.len) break :blk &.{};
                    const data = buffer[pos .. pos + 2];
                    pos += 2;
                    break :blk data;
                },
                .start_field => blk: {
                    if (pos + 1 > buffer.len) break :blk &.{};
                    const data = buffer[pos .. pos + 1];
                    pos += 1;
                    break :blk data;
                },
                else => &.{},
            };

            const order = Order{
                .code = code,
                .data = try self.allocator.dupe(u8, order_data),
            };
            try orders.append(self.allocator, order);
        }

        return orders;
    }
};

test "command parser parse simple command" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{@intFromEnum(protocol.CommandCode.write)};
    const cmd = try parser.parse_command(buffer);

    try std.testing.expect(cmd != null);
    if (cmd) |c| {
        try std.testing.expectEqual(protocol.CommandCode.write, c.code);
        try std.testing.expectEqual(@as(usize, 0), c.data.len);
        var cmd_copy = c;
        cmd_copy.deinit(std.testing.allocator);
    }
}

test "command parser parse command with data" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{ @intFromEnum(protocol.CommandCode.erase_write), 0x42, 0x43 };
    const cmd = try parser.parse_command(buffer);

    try std.testing.expect(cmd != null);
    if (cmd) |c| {
        try std.testing.expectEqual(protocol.CommandCode.erase_write, c.code);
        try std.testing.expectEqual(@as(usize, 2), c.data.len);
        try std.testing.expectEqual(@as(u8, 0x42), c.data[0]);
        var cmd_copy = c;
        cmd_copy.deinit(std.testing.allocator);
    }
}

test "command parser invalid command code" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{0xFF};
    const result = parser.parse_command(buffer);
    try std.testing.expectError(error.InvalidCommandCode, result);
}

test "command parser parse order set buffer address" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{ @intFromEnum(protocol.OrderCode.set_buffer_address), 0x00, 0x14 };
    var orders = try parser.parse_orders(buffer);
    defer {
        for (orders.items) |*order| {
            order.deinit(std.testing.allocator);
        }
        orders.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), orders.items.len);
    try std.testing.expectEqual(protocol.OrderCode.set_buffer_address, orders.items[0].code);
    try std.testing.expectEqual(@as(usize, 2), orders.items[0].data.len);
}

test "command parser parse order start field" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{ @intFromEnum(protocol.OrderCode.start_field), 0x01 };
    var orders = try parser.parse_orders(buffer);
    defer {
        for (orders.items) |*order| {
            order.deinit(std.testing.allocator);
        }
        orders.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), orders.items.len);
    try std.testing.expectEqual(protocol.OrderCode.start_field, orders.items[0].code);
    try std.testing.expectEqual(@as(usize, 1), orders.items[0].data.len);
}

test "command parser parse multiple orders" {
    var parser = CommandParser.init(std.testing.allocator);

    const buffer = &.{
        @intFromEnum(protocol.OrderCode.set_buffer_address), 0x00, 0x00,
        @intFromEnum(protocol.OrderCode.start_field),        0x01,
    };
    var orders = try parser.parse_orders(buffer);
    defer {
        for (orders.items) |*order| {
            order.deinit(std.testing.allocator);
        }
        orders.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), orders.items.len);
    try std.testing.expectEqual(protocol.OrderCode.set_buffer_address, orders.items[0].code);
    try std.testing.expectEqual(protocol.OrderCode.start_field, orders.items[1].code);
}
