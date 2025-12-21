const std = @import("std");
const screen = @import("screen.zig");
const terminal = @import("terminal.zig");
const field = @import("field.zig");
const input = @import("input.zig");
const parser = @import("parser.zig");
const stream_parser = @import("stream_parser.zig");
const executor = @import("executor.zig");
const command = @import("command.zig");
const data_entry = @import("data_entry.zig");
const protocol = @import("protocol.zig");
const renderer = @import("renderer.zig");
const attributes = @import("attributes.zig");

/// High-level 3270 emulator facade
/// Combines screen, terminal, field, and input management into a single interface.
pub const Emulator = struct {
    allocator: std.mem.Allocator,
    screen_buffer: screen.Screen,
    terminal_state: terminal.Terminal,
    field_manager: field.FieldManager,
    input_handler: input.InputHandler,

    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Emulator {
        var scr = try screen.Screen.init(allocator, rows, cols);
        errdefer scr.deinit();

        var field_mgr = field.FieldManager.init(allocator);
        errdefer field_mgr.deinit();

        var input_handler = input.InputHandler.init(allocator);
        errdefer input_handler.deinit();

        const term = terminal.Terminal.init(allocator, &scr);

        return Emulator{
            .allocator = allocator,
            .screen_buffer = scr,
            .terminal_state = term,
            .field_manager = field_mgr,
            .input_handler = input_handler,
        };
    }

    pub fn deinit(self: *Emulator) void {
        self.input_handler.deinit();
        self.field_manager.deinit();
        self.screen_buffer.deinit();
    }

    /// Get screen dimensions
    pub fn screen_size(self: *const Emulator) struct { rows: u16, cols: u16 } {
        return .{
            .rows = self.screen_buffer.rows,
            .cols = self.screen_buffer.cols,
        };
    }

    /// Clear entire screen
    pub fn clear_screen(self: *Emulator) void {
        self.screen_buffer.clear();
    }

    /// Write a character at position
    pub fn write_char(self: *Emulator, row: u16, col: u16, char: u8) !void {
        try self.screen_buffer.write_char(row, col, char);
    }

    /// Write a string at current cursor position
    pub fn write_string(self: *Emulator, text: []const u8) !void {
        try self.terminal_state.write_string(text);
    }

    /// Read a character at position
    pub fn read_char(self: *Emulator, row: u16, col: u16) !u8 {
        return self.screen_buffer.read_char(row, col);
    }

    /// Render screen to display
    pub fn render(self: *Emulator) !void {
        try self.terminal_state.render();
    }

    /// Add a new field to the field manager
    pub fn add_field(self: *Emulator, start: u16, length: u16, field_attrs: protocol.FieldAttribute) !void {
        _ = try self.field_manager.add_field(start, length, field_attrs);
    }

    /// Get number of fields
    pub fn field_count(self: *Emulator) usize {
        return self.field_manager.count();
    }
};

test "emulator init and deinit" {
    var em = try Emulator.init(std.testing.allocator, 24, 80);
    defer em.deinit();

    const size = em.screen_size();
    try std.testing.expectEqual(@as(u16, 24), size.rows);
    try std.testing.expectEqual(@as(u16, 80), size.cols);
}

test "emulator write and read char" {
    var em = try Emulator.init(std.testing.allocator, 24, 80);
    defer em.deinit();

    try em.write_char(0, 0, 'X');
    const char = try em.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'X'), char);
}

test "emulator clear screen" {
    var em = try Emulator.init(std.testing.allocator, 24, 80);
    defer em.deinit();

    try em.write_char(0, 0, 'A');
    em.clear_screen();
    const char = try em.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}

test "emulator field management" {
    var em = try Emulator.init(std.testing.allocator, 24, 80);
    defer em.deinit();

    try em.add_field(0, 20, .{});
    try std.testing.expectEqual(@as(usize, 1), em.field_count());
}
