/// Integration of libghostty-vt with the 3270 terminal emulator.
/// Provides VT sequence parsing capabilities alongside 3270 protocol handling.
const std = @import("std");
const ghostty_vt = @import("ghostty_vt");
const screen = @import("screen.zig");

/// Terminal that supports both 3270 and VT sequences via libghostty-vt
pub const GhosttyVtTerminal = struct {
    allocator: std.mem.Allocator,
    vt_terminal: ghostty_vt.Terminal,
    screen: *screen.Screen,
    cursor_row: u16,
    cursor_col: u16,

    /// Initialize a ghostty-vt backed terminal
    pub fn init(
        allocator: std.mem.Allocator,
        scr: *screen.Screen,
    ) !GhosttyVtTerminal {
        const vt_term = try ghostty_vt.Terminal.init(allocator, .{
            .cols = scr.cols,
            .rows = scr.rows,
        });

        return GhosttyVtTerminal{
            .allocator = allocator,
            .vt_terminal = vt_term,
            .screen = scr,
            .cursor_row = 0,
            .cursor_col = 0,
        };
    }

    /// Deinitialize the terminal
    pub fn deinit(self: *GhosttyVtTerminal) void {
        self.vt_terminal.deinit(self.allocator);
    }

    /// Process a VT sequence from input
    pub fn processVtSequence(self: *GhosttyVtTerminal, sequence: []const u8) !void {
        for (sequence) |byte| {
            try self.vt_terminal.processByte(byte);
        }
    }

    /// Write text using ghostty-vt's terminal
    pub fn write_string(self: *GhosttyVtTerminal, str: []const u8) !void {
        try self.vt_terminal.printString(str);
    }

    /// Get the current terminal state as plain text
    pub fn getTerminalOutput(self: *GhosttyVtTerminal) ![]const u8 {
        return try self.vt_terminal.plainString(self.allocator);
    }

    /// Sync ghostty-vt terminal state to screen buffer
    pub fn syncToScreen(self: *GhosttyVtTerminal) !void {
        const output = try self.getTerminalOutput();
        defer self.allocator.free(output);

        var row: u16 = 0;
        var col: u16 = 0;

        for (output) |char| {
            if (char == '\n') {
                row += 1;
                col = 0;
                if (row >= self.screen.rows) break;
            } else {
                if (col < self.screen.cols) {
                    try self.screen.write_char(row, col, char);
                    col += 1;
                }
            }
        }
    }

    /// Move cursor to position
    pub fn move_cursor(self: *GhosttyVtTerminal, row: u16, col: u16) !void {
        if (row >= self.screen.rows or col >= self.screen.cols) {
            return error.OutOfBounds;
        }
        self.cursor_row = row;
        self.cursor_col = col;
    }

    /// Render screen to stdout
    pub fn render(self: *GhosttyVtTerminal) !void {
        try self.syncToScreen();

        std.debug.print("\x1B[2J\x1B[H", .{});

        for (0..self.screen.rows) |row| {
            for (0..self.screen.cols) |col| {
                const char = self.screen.buffer[row][col];
                std.debug.print("{c}", .{char});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("\x1B[{};{}H", .{ self.cursor_row + 1, self.cursor_col + 1 });
    }

    /// Clear terminal
    pub fn clear(self: *GhosttyVtTerminal) void {
        self.screen.clear();
        self.cursor_row = 0;
        self.cursor_col = 0;
    }
};

test "ghostty vt terminal initialization" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    var term = try GhosttyVtTerminal.init(std.testing.allocator, &scr);
    defer term.deinit();

    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_col);
}

test "ghostty vt terminal write string" {
    var scr = try screen.Screen.init(std.testing.allocator, 10, 40);
    defer scr.deinit();

    var term = try GhosttyVtTerminal.init(std.testing.allocator, &scr);
    defer term.deinit();

    try term.write_string("Hello from ghostty-vt!");
    const output = try term.getTerminalOutput();
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Hello"));
}

test "ghostty vt terminal sync to screen" {
    var scr = try screen.Screen.init(std.testing.allocator, 5, 20);
    defer scr.deinit();

    var term = try GhosttyVtTerminal.init(std.testing.allocator, &scr);
    defer term.deinit();

    try term.write_string("Test");
    try term.syncToScreen();

    const char0 = try scr.read_char(0, 0);
    const char1 = try scr.read_char(0, 1);
    const char2 = try scr.read_char(0, 2);
    const char3 = try scr.read_char(0, 3);

    try std.testing.expectEqual(@as(u8, 'T'), char0);
    try std.testing.expectEqual(@as(u8, 'e'), char1);
    try std.testing.expectEqual(@as(u8, 's'), char2);
    try std.testing.expectEqual(@as(u8, 't'), char3);
}

test "ghostty vt terminal move cursor" {
    var scr = try screen.Screen.init(std.testing.allocator, 10, 10);
    defer scr.deinit();

    var term = try GhosttyVtTerminal.init(std.testing.allocator, &scr);
    defer term.deinit();

    try term.move_cursor(5, 5);

    try std.testing.expectEqual(@as(u16, 5), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), term.cursor_col);
}
