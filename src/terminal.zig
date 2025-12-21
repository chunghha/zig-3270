const std = @import("std");
const screen = @import("screen.zig");

/// Terminal rendering with ANSI escape sequences
/// Future: integrate libxghostty for advanced rendering
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    screen: *screen.Screen,
    cursor_row: u16,
    cursor_col: u16,

    pub fn init(allocator: std.mem.Allocator, scr: *screen.Screen) Terminal {
        return Terminal{
            .allocator = allocator,
            .screen = scr,
            .cursor_row = 0,
            .cursor_col = 0,
        };
    }

    /// Write character at current cursor position and advance
    pub fn write_char(self: *Terminal, char: u8) !void {
        try self.screen.write_char(self.cursor_row, self.cursor_col, char);
        self.cursor_col += 1;
        if (self.cursor_col >= self.screen.cols) {
            self.cursor_col = 0;
            self.cursor_row += 1;
            if (self.cursor_row >= self.screen.rows) {
                self.cursor_row = self.screen.rows - 1;
            }
        }
    }

    /// Write string at current cursor position
    pub fn write_string(self: *Terminal, str: []const u8) !void {
        for (str) |char| {
            try self.write_char(char);
        }
    }

    /// Move cursor to position
    pub fn move_cursor(self: *Terminal, row: u16, col: u16) !void {
        if (row >= self.screen.rows or col >= self.screen.cols) {
            return error.OutOfBounds;
        }
        self.cursor_row = row;
        self.cursor_col = col;
    }

    /// Get current cursor position
    pub fn cursor_position(self: *Terminal) struct { row: u16, col: u16 } {
        return .{ .row = self.cursor_row, .col = self.cursor_col };
    }

    /// Render screen to stdout with ANSI escape sequences
    pub fn render(self: *Terminal) !void {
        // Clear screen and move to home
        std.debug.print("\x1B[2J\x1B[H", .{});

        for (0..self.screen.rows) |row| {
            for (0..self.screen.cols) |col| {
                const char = self.screen.buffer[row][col];
                std.debug.print("{c}", .{char});
            }
            std.debug.print("\n", .{});
        }

        // Move cursor to current position
        std.debug.print("\x1B[{};{}H", .{ self.cursor_row + 1, self.cursor_col + 1 });
    }

    /// Clear entire screen
    pub fn clear(self: *Terminal) void {
        self.screen.clear();
        self.cursor_row = 0;
        self.cursor_col = 0;
    }
};

test "terminal initialization" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    const term = Terminal.init(std.testing.allocator, &scr);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_col);
}

test "terminal write char" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 3);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    try term.write_char('A');

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'A'), char);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), term.cursor_col);
}

test "terminal write string" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 10);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    try term.write_string("Hello");

    try std.testing.expectEqual(@as(u8, 'H'), try scr.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'e'), try scr.read_char(0, 1));
    try std.testing.expectEqual(@as(u8, 'l'), try scr.read_char(0, 2));
}

test "terminal move cursor" {
    var scr = try screen.Screen.init(std.testing.allocator, 10, 10);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    try term.move_cursor(5, 5);

    try std.testing.expectEqual(@as(u16, 5), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), term.cursor_col);
}

test "terminal move cursor out of bounds" {
    var scr = try screen.Screen.init(std.testing.allocator, 10, 10);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    const result = term.move_cursor(15, 15);
    try std.testing.expectError(error.OutOfBounds, result);
}

test "terminal cursor wrapping" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 3);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    try term.write_string("ABCDE");

    try std.testing.expectEqual(@as(u16, 1), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), term.cursor_col);
}

test "terminal clear" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 2);
    defer scr.deinit();

    var term = Terminal.init(std.testing.allocator, &scr);
    try term.write_char('X');
    term.clear();

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
}
