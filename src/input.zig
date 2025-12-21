const std = @import("std");

/// Keyboard key codes
pub const KeyCode = enum(u8) {
    enter = 0x0D,
    backspace = 0x08,
    tab = 0x09,
    escape = 0x1B,
    home = 0x01,
    end = 0x05,
    clear = 0x0F,
    pa1 = 0x6C,
    pa2 = 0x6E,
    pa3 = 0x6B,
};

/// Keyboard input handler
pub const InputHandler = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    /// Initialize input handler
    pub fn init(allocator: std.mem.Allocator) InputHandler {
        return InputHandler{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch std.ArrayList(u8){
                .items = &.{},
                .capacity = 0,
            },
        };
    }

    /// Deallocate input handler
    pub fn deinit(self: *InputHandler) void {
        self.buffer.deinit(self.allocator);
    }

    /// Queue a key press
    pub fn queue_key(self: *InputHandler, key: u8) !void {
        try self.buffer.append(self.allocator, key);
    }

    /// Get next queued key (non-blocking)
    pub fn get_key(self: *InputHandler) ?u8 {
        if (self.buffer.items.len == 0) {
            return null;
        }
        return self.buffer.orderedRemove(0);
    }

    /// Check if there are buffered keys
    pub fn has_input(self: *InputHandler) bool {
        return self.buffer.items.len > 0;
    }

    /// Clear input buffer
    pub fn clear(self: *InputHandler) void {
        self.buffer.clearRetainingCapacity();
    }
};

test "input handler initialization" {
    var handler = InputHandler.init(std.testing.allocator);
    defer handler.deinit();
    try std.testing.expect(!handler.has_input());
}

test "input handler queue and get key" {
    var handler = InputHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.queue_key('A');
    try std.testing.expect(handler.has_input());

    const key = handler.get_key();
    try std.testing.expectEqual(@as(?u8, 'A'), key);
    try std.testing.expect(!handler.has_input());
}

test "input handler fifo order" {
    var handler = InputHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.queue_key('A');
    try handler.queue_key('B');
    try handler.queue_key('C');

    try std.testing.expectEqual(@as(?u8, 'A'), handler.get_key());
    try std.testing.expectEqual(@as(?u8, 'B'), handler.get_key());
    try std.testing.expectEqual(@as(?u8, 'C'), handler.get_key());
    try std.testing.expectEqual(@as(?u8, null), handler.get_key());
}

test "input handler clear" {
    var handler = InputHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.queue_key('X');
    handler.clear();
    try std.testing.expect(!handler.has_input());
}
