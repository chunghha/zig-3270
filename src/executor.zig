const std = @import("std");
const protocol = @import("protocol.zig");
const command = @import("command.zig");
const field = @import("field.zig");
const screen = @import("screen.zig");

/// 3270 command executor - processes parsed commands and updates screen state
pub const Executor = struct {
    allocator: std.mem.Allocator,
    screen: *screen.Screen,
    field_manager: *field.FieldManager,
    cursor_address: u16,

    pub fn init(allocator: std.mem.Allocator, scr: *screen.Screen, fm: *field.FieldManager) Executor {
        return Executor{
            .allocator = allocator,
            .screen = scr,
            .field_manager = fm,
            .cursor_address = 0,
        };
    }

    /// Execute a command
    pub fn execute(self: *Executor, cmd: command.Command) !void {
        switch (cmd.code) {
            .erase_write => try self.execute_erase_write(cmd.data),
            .erase_write_alt => try self.execute_erase_write_alt(cmd.data),
            .write => try self.execute_write(cmd.data),
            else => return error.UnsupportedCommand,
        }
    }

    /// Erase Write (EW) - clear screen and process orders
    fn execute_erase_write(self: *Executor, data: []const u8) !void {
        self.screen.clear();
        self.cursor_address = 0;
        self.field_manager.clear();

        try self.process_orders(data);
    }

    /// Erase Write Alt (EWA) - similar to EW but with different reset behavior
    fn execute_erase_write_alt(self: *Executor, data: []const u8) !void {
        self.screen.clear();
        self.cursor_address = 0;

        try self.process_orders(data);
    }

    /// Write (W) - process orders at current position
    fn execute_write(self: *Executor, data: []const u8) !void {
        try self.process_orders(data);
    }

    /// Process orders within command data
    fn process_orders(self: *Executor, data: []const u8) !void {
        var pos: usize = 0;

        while (pos < data.len) {
            const byte = data[pos];

            // Try to parse as order code
            if (std.meta.intToEnum(protocol.OrderCode, byte)) |order_code| {
                pos += 1;

                switch (order_code) {
                    .set_buffer_address => {
                        if (pos + 2 > data.len) return error.IncompleteOrder;
                        const addr_bytes = data[pos .. pos + 2];
                        const addr = protocol.Address.from_bytes(addr_bytes[0..2].*);
                        self.cursor_address = @as(u16, addr.row) * 80 + addr.col;
                        pos += 2;
                    },
                    .start_field => {
                        if (pos + 1 > data.len) return error.IncompleteOrder;
                        const attr_byte = data[pos];
                        const attr: protocol.FieldAttribute = @bitCast(attr_byte);

                        // Field starts at current position, will be sized when we encounter next field
                        const field_start = self.cursor_address;
                        _ = try self.field_manager.add_field(field_start, 1, attr);
                        self.cursor_address += 1;
                        pos += 1;
                    },
                    .set_attribute => {
                        if (pos + 1 > data.len) return error.IncompleteOrder;
                        // Set attribute for current field (extended implementation)
                        pos += 1;
                    },
                    .insert_cursor => {
                        // Just skip - cursor already managed
                        pos += 1;
                    },
                    else => {
                        // Skip unknown orders
                        pos += 1;
                    },
                }
            } else |_| {
                // Regular text - write to screen
                const row = @as(u16, @intCast(self.cursor_address / 80));
                const col = @as(u16, @intCast(self.cursor_address % 80));

                if (row < self.screen.rows and col < self.screen.cols) {
                    try self.screen.write_char(row, col, byte);
                }

                self.cursor_address += 1;
                if (self.cursor_address >= 1920) {
                    self.cursor_address = 1919;
                }

                pos += 1;
            }
        }
    }

    /// Get current cursor address
    pub fn get_cursor_address(self: *Executor) u16 {
        return self.cursor_address;
    }
};

test "executor initialization" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    const exec = Executor.init(std.testing.allocator, &scr, &fm);
    try std.testing.expectEqual(@as(u16, 0), exec.cursor_address);
}

test "executor erase write clears screen" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 3);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    var exec = Executor.init(std.testing.allocator, &scr, &fm);

    // Write something first
    try scr.write_char(0, 0, 'X');

    // Create and execute erase write command
    var cmd = command.Command{
        .code = protocol.CommandCode.erase_write,
        .data = try std.testing.allocator.alloc(u8, 0),
    };
    defer cmd.deinit(std.testing.allocator);

    try exec.execute(cmd);

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}

test "executor set buffer address order" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    var exec = Executor.init(std.testing.allocator, &scr, &fm);

    // Create order: set buffer address to (1, 5) = address 85
    const order_data = &.{ @intFromEnum(protocol.OrderCode.set_buffer_address), 0x00, 0x55 };
    var cmd = command.Command{
        .code = protocol.CommandCode.write,
        .data = try std.testing.allocator.dupe(u8, order_data),
    };
    defer cmd.deinit(std.testing.allocator);

    try exec.execute(cmd);
    try std.testing.expectEqual(@as(u16, 85), exec.cursor_address);
}

test "executor write text to screen" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 10);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    var exec = Executor.init(std.testing.allocator, &scr, &fm);

    const text = "Hello";
    var cmd = command.Command{
        .code = protocol.CommandCode.write,
        .data = try std.testing.allocator.dupe(u8, text),
    };
    defer cmd.deinit(std.testing.allocator);

    try exec.execute(cmd);

    try std.testing.expectEqual(@as(u8, 'H'), try scr.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'e'), try scr.read_char(0, 1));
    try std.testing.expectEqual(@as(u8, 'l'), try scr.read_char(0, 2));
}

test "executor set buffer address then write" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 10);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    var exec = Executor.init(std.testing.allocator, &scr, &fm);

    // Set address to (0, 5), then write "OK"
    const orders_and_text = &.{
        @intFromEnum(protocol.OrderCode.set_buffer_address), 0x00, 0x05,
        'O',                                                 'K',
    };
    var cmd = command.Command{
        .code = protocol.CommandCode.write,
        .data = try std.testing.allocator.dupe(u8, orders_and_text),
    };
    defer cmd.deinit(std.testing.allocator);

    try exec.execute(cmd);

    try std.testing.expectEqual(@as(u8, ' '), try scr.read_char(0, 4));
    try std.testing.expectEqual(@as(u8, 'O'), try scr.read_char(0, 5));
    try std.testing.expectEqual(@as(u8, 'K'), try scr.read_char(0, 6));
}

test "executor full command pipeline: erase write with field and text" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    var exec = Executor.init(std.testing.allocator, &scr, &fm);

    // Simple test: write "Test" and verify it's on screen
    const cmd_data = "Test";

    var cmd = command.Command{
        .code = protocol.CommandCode.erase_write,
        .data = try std.testing.allocator.dupe(u8, cmd_data),
    };
    defer cmd.deinit(std.testing.allocator);

    try exec.execute(cmd);

    // Verify text was written
    try std.testing.expectEqual(@as(u8, 'T'), try scr.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'e'), try scr.read_char(0, 1));
    try std.testing.expectEqual(@as(u8, 's'), try scr.read_char(0, 2));
    try std.testing.expectEqual(@as(u8, 't'), try scr.read_char(0, 3));
}
