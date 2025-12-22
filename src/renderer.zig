const std = @import("std");
const screen = @import("screen.zig");

/// Renderer using libxghostty
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    screen: *screen.Screen,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
    show_status: bool = true,

    /// Initialize renderer with a screen buffer
    pub fn init(allocator: std.mem.Allocator, scr: *screen.Screen) Renderer {
        return Renderer{
            .allocator = allocator,
            .screen = scr,
        };
    }

    /// Render screen contents to stdout (placeholder for libxghostty)
    pub fn render(self: *Renderer) !void {
        // Clear and home cursor
        std.debug.print("\x1B[2J\x1B[H", .{});

        // Render screen content
        for (0..self.screen.rows) |row| {
            for (0..self.screen.cols) |col| {
                const char = self.screen.buffer[row][col];
                std.debug.print("{c}", .{char});
            }
            std.debug.print("\n", .{});
        }

        // Render status line if enabled
        if (self.show_status) {
            try self.render_status_line();
        }

        // Position cursor
        try self.position_cursor(self.cursor_row, self.cursor_col);
    }

    /// Set cursor position (row, col)
    pub fn set_cursor(self: *Renderer, row: u16, col: u16) void {
        self.cursor_row = row;
        self.cursor_col = col;
    }

    /// Get cursor position
    pub fn get_cursor(self: Renderer) struct { row: u16, col: u16 } {
        return .{
            .row = self.cursor_row,
            .col = self.cursor_col,
        };
    }

    /// Move cursor to position using ANSI escape sequences
    fn position_cursor(_: Renderer, row: u16, col: u16) !void {
        const stdout = std.io.getStdOut();
        var writer = stdout.writer();

        // ANSI escape: ESC[{row};{col}H
        try writer.print("\x1B[{};{}H", .{ row + 1, col + 1 });
    }

    /// Render status line showing connection state
    fn render_status_line(self: Renderer) !void {
        const stdout = std.io.getStdOut();
        var writer = stdout.writer();

        // Position at bottom of screen
        try writer.print("\x1B[{};0H", .{self.screen.rows + 1});

        // Write status (placeholder)
        try writer.writeAll("Status: Connected | Press Ctrl+C to quit");

        // Clear to end of line
        try writer.writeAll("\x1B[0K");
    }

    /// Clear the rendered display
    pub fn clear(self: *Renderer) void {
        self.screen.clear();
    }

    /// Set a cell at position (row, col) with a character
    pub fn set_cell(self: *Renderer, row: u16, col: u16, char: u8) !void {
        try self.screen.write_char(row, col, char);
    }

    /// Enable/disable status line
    pub fn set_show_status(self: *Renderer, show: bool) void {
        self.show_status = show;
    }
};

test "renderer initialization" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    const rend = Renderer.init(std.testing.allocator, &scr);
    try std.testing.expectEqual(@as(u16, 24), rend.screen.rows);
}

test "renderer set cell" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 3);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);
    try rend.set_cell(0, 0, 'X');

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'X'), char);
}

test "renderer clear" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 2);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);
    try rend.set_cell(0, 0, 'Y');
    rend.clear();

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}

test "renderer cursor positioning" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);

    // Set cursor position
    rend.set_cursor(5, 10);
    const pos = rend.get_cursor();

    try std.testing.expectEqual(@as(u16, 5), pos.row);
    try std.testing.expectEqual(@as(u16, 10), pos.col);
}

test "renderer status line toggle" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);

    try std.testing.expect(rend.show_status);
    rend.set_show_status(false);
    try std.testing.expect(!rend.show_status);
}
