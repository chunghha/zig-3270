const std = @import("std");
const emulator_mod = @import("emulator.zig");
const client_mod = @import("client.zig");
const renderer_mod = @import("renderer.zig");
const input_mod = @import("input.zig");

pub const TerminalState = enum {
    disconnected,
    connecting,
    connected,
    waiting_for_response,
};

pub const InteractiveTerminal = struct {
    allocator: std.mem.Allocator,
    running: bool = true,
    state: TerminalState = .disconnected,
    emulator: emulator_mod.Emulator,
    renderer: renderer_mod.Renderer,

    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !InteractiveTerminal {
        var emu = try emulator_mod.Emulator.init(allocator, rows, cols);
        errdefer emu.deinit();

        const rend = renderer_mod.Renderer.init(allocator, &emu.screen_buffer);

        return .{
            .allocator = allocator,
            .emulator = emu,
            .renderer = rend,
        };
    }

    pub fn deinit(self: *InteractiveTerminal) void {
        self.emulator.deinit();
    }

    /// Set terminal state
    pub fn set_state(self: *InteractiveTerminal, new_state: TerminalState) void {
        self.state = new_state;
    }

    /// Get current terminal state
    pub fn get_state(self: InteractiveTerminal) TerminalState {
        return self.state;
    }

    /// Handle a keyboard input event
    pub fn handle_keypress(
        self: *InteractiveTerminal,
        key_code: u8,
    ) !void {
        // Queue the key for processing
        try self.emulator.input_handler.queue_key(key_code);
    }

    /// Process queued keys and send to server
    pub fn process_input(self: *InteractiveTerminal) !void {
        while (self.emulator.input_handler.has_input()) {
            const key = self.emulator.input_handler.get_key() orelse break;
            // In real implementation, would send to network
            _ = key;
        }
    }

    /// Refresh terminal display
    pub fn refresh_display(self: *InteractiveTerminal) !void {
        try self.renderer.render();
    }

    /// Signal terminal to stop running
    pub fn stop(self: *InteractiveTerminal) void {
        self.running = false;
    }

    /// Check if terminal is still running
    pub fn is_running(self: InteractiveTerminal) bool {
        return self.running;
    }
};

// Tests
test "interactive terminal init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    try std.testing.expectEqual(TerminalState.disconnected, term.get_state());
    try std.testing.expect(term.is_running());
}

test "interactive terminal state transitions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    try std.testing.expectEqual(TerminalState.disconnected, term.get_state());

    term.set_state(.connecting);
    try std.testing.expectEqual(TerminalState.connecting, term.get_state());

    term.set_state(.connected);
    try std.testing.expectEqual(TerminalState.connected, term.get_state());

    term.set_state(.disconnected);
    try std.testing.expectEqual(TerminalState.disconnected, term.get_state());
}

test "interactive terminal stop running" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    try std.testing.expect(term.is_running());
    term.stop();
    try std.testing.expect(!term.is_running());
}

test "interactive terminal handle keypress" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    try term.handle_keypress(0x41); // 'A'
    try std.testing.expect(term.emulator.input_handler.has_input());
}

test "interactive terminal process input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    try term.handle_keypress(0x41); // 'A'
    try term.process_input();
    try std.testing.expect(!term.emulator.input_handler.has_input());
}

test "interactive terminal state after init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try InteractiveTerminal.init(allocator, 24, 80);
    defer term.deinit();

    // Verify initial state is disconnected and running
    try std.testing.expectEqual(TerminalState.disconnected, term.get_state());
    try std.testing.expect(term.is_running());
}
