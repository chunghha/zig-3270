const std = @import("std");
const field = @import("field.zig");
const screen = @import("screen.zig");
const parse_utils = @import("parse_utils.zig");

/// Data entry manager - handles keyboard input to unprotected fields
pub const DataEntry = struct {
    allocator: std.mem.Allocator,
    field_manager: *field.FieldManager,
    screen: *screen.Screen,
    current_field_index: ?usize,
    field_cursor: u16, // Position within current field

    pub fn init(allocator: std.mem.Allocator, fm: *field.FieldManager, scr: *screen.Screen) DataEntry {
        return DataEntry{
            .allocator = allocator,
            .field_manager = fm,
            .screen = scr,
            .current_field_index = null,
            .field_cursor = 0,
        };
    }

    /// Move to first unprotected field
    pub fn home(self: *DataEntry) !void {
        for (0..self.field_manager.count()) |i| {
            if (self.field_manager.get_field(i)) |f| {
                if (!f.attribute.protected) {
                    self.current_field_index = i;
                    self.field_cursor = 0;
                    return;
                }
            }
        }
        return error.NoUnprotectedFields;
    }

    /// Move to next unprotected field
    pub fn tab(self: *DataEntry) !void {
        const start_idx = if (self.current_field_index) |idx| idx + 1 else 0;

        for (start_idx..self.field_manager.count()) |i| {
            if (self.field_manager.get_field(i)) |f| {
                if (!f.attribute.protected) {
                    self.current_field_index = i;
                    self.field_cursor = 0;
                    return;
                }
            }
        }

        // Wrap around
        for (0..start_idx) |i| {
            if (self.field_manager.get_field(i)) |f| {
                if (!f.attribute.protected) {
                    self.current_field_index = i;
                    self.field_cursor = 0;
                    return;
                }
            }
        }

        return error.NoUnprotectedFields;
    }

    /// Write character to current field
    pub fn write_char(self: *DataEntry, char: u8) !void {
        if (self.current_field_index == null) {
            try self.home();
        }

        const idx = self.current_field_index orelse return error.NoCurrentField;
        const f = self.field_manager.get_field(idx) orelse return error.InvalidFieldIndex;

        if (f.attribute.protected) {
            return error.FieldProtected;
        }

        if (self.field_cursor >= f.length) {
            return error.FieldFull;
        }

        try f.set_char(self.field_cursor, char);

        // Also update screen
        const screen_offset = f.start_address + self.field_cursor;
        const addr = parse_utils.buffer_to_address(screen_offset);
        const row = @as(u16, @intCast(addr.row));
        const col = @as(u16, @intCast(addr.col));

        if (row < self.screen.rows and col < self.screen.cols) {
            try self.screen.write_char(row, col, char);
        }

        self.field_cursor += 1;
    }

    /// Delete character at field cursor
    pub fn backspace(self: *DataEntry) !void {
        if (self.current_field_index == null) {
            return error.NoCurrentField;
        }

        if (self.field_cursor == 0) {
            return error.AlreadyAtFieldStart;
        }

        const idx = self.current_field_index orelse return error.NoCurrentField;
        const f = self.field_manager.get_field(idx) orelse return error.InvalidFieldIndex;

        self.field_cursor -= 1;

        try f.set_char(self.field_cursor, ' ');

        // Also update screen
        const screen_offset = f.start_address + self.field_cursor;
        const addr = parse_utils.buffer_to_address(screen_offset);
        const row = @as(u16, @intCast(addr.row));
        const col = @as(u16, @intCast(addr.col));

        if (row < self.screen.rows and col < self.screen.cols) {
            try self.screen.write_char(row, col, ' ');
        }
    }

    /// Get content of current field
    pub fn get_field_content(self: *DataEntry) ![]const u8 {
        if (self.current_field_index == null) {
            try self.home();
        }

        const idx = self.current_field_index orelse return error.NoCurrentField;
        const f = self.field_manager.get_field(idx) orelse return error.InvalidFieldIndex;

        return f.content;
    }

    /// Clear current field
    pub fn clear_field(self: *DataEntry) !void {
        if (self.current_field_index == null) {
            try self.home();
        }

        const idx = self.current_field_index orelse return error.NoCurrentField;
        const f = self.field_manager.get_field(idx) orelse return error.InvalidFieldIndex;

        @memset(f.content, ' ');

        // Update screen
        for (0..f.length) |offset| {
            const screen_offset = f.start_address + offset;
            const addr = parse_utils.buffer_to_address(screen_offset);
            const row = @as(u16, @intCast(addr.row));
            const col = @as(u16, @intCast(addr.col));

            if (row < self.screen.rows and col < self.screen.cols) {
                try self.screen.write_char(row, col, ' ');
            }
        }

        self.field_cursor = 0;
    }

    /// Get current field address
    pub fn current_address(self: *DataEntry) !u16 {
        if (self.current_field_index == null) {
            try self.home();
        }

        const idx = self.current_field_index orelse return error.NoCurrentField;
        const f = self.field_manager.get_field(idx) orelse return error.InvalidFieldIndex;

        return f.start_address + self.field_cursor;
    }
};

test "data entry home finds first unprotected field" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = true });
    _ = try fm.add_field(10, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.home();

    try std.testing.expectEqual(@as(?usize, 1), de.current_field_index);
    try std.testing.expectEqual(@as(u16, 0), de.field_cursor);
}

test "data entry tab moves to next unprotected field" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 30);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });
    _ = try fm.add_field(10, 10, .{ .protected = true });
    _ = try fm.add_field(20, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.home();

    try std.testing.expectEqual(@as(?usize, 0), de.current_field_index);

    try de.tab();
    try std.testing.expectEqual(@as(?usize, 2), de.current_field_index);
}

test "data entry write char to field" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.write_char('A');
    try de.write_char('B');
    try de.write_char('C');

    const content = try de.get_field_content();
    try std.testing.expectEqual(@as(u8, 'A'), content[0]);
    try std.testing.expectEqual(@as(u8, 'B'), content[1]);
    try std.testing.expectEqual(@as(u8, 'C'), content[2]);
}

test "data entry write to screen updates display" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 15);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.write_char('X');

    const screen_char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'X'), screen_char);
}

test "data entry backspace removes character" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.write_char('A');
    try de.write_char('B');
    try de.backspace();

    const content = try de.get_field_content();
    try std.testing.expectEqual(@as(u8, 'A'), content[0]);
    try std.testing.expectEqual(@as(u8, ' '), content[1]);
}

test "data entry clear field" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.write_char('A');
    try de.write_char('B');
    try de.clear_field();

    const content = try de.get_field_content();
    try std.testing.expectEqual(@as(u8, ' '), content[0]);
    try std.testing.expectEqual(@as(u8, ' '), content[1]);
}

test "data entry protected field rejected" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = true });
    _ = try fm.add_field(10, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.home(); // Should go to field 1 (unprotected)

    try std.testing.expectEqual(@as(?usize, 1), de.current_field_index);
}

test "data entry current address" {
    var scr = try screen.Screen.init(std.testing.allocator, 3, 20);
    defer scr.deinit();

    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(5, 10, .{ .protected = false });

    var de = DataEntry.init(std.testing.allocator, &fm, &scr);
    try de.home();

    const addr = try de.current_address();
    try std.testing.expectEqual(@as(u16, 5), addr);
}
