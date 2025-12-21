const std = @import("std");
const protocol = @import("protocol.zig");

/// Keyboard configuration management
pub const KeyboardConfig = struct {
    bindings: std.StringHashMap(protocol.AID),
    allocator: std.mem.Allocator,

    /// Initialize empty keyboard configuration
    pub fn init(allocator: std.mem.Allocator) KeyboardConfig {
        return .{
            .bindings = std.StringHashMap(protocol.AID).init(allocator),
            .allocator = allocator,
        };
    }

    /// Load configuration from JSON file
    pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) !KeyboardConfig {
        var config = KeyboardConfig.init(allocator);

        // Try to open the file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return config; // Return empty config if file not found
            }
            return err;
        };
        defer file.close();

        // Read file contents
        const max_size = 64 * 1024; // 64 KB max config size
        const content = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(content);

        // Parse JSON
        try config.parse_json(content);

        return config;
    }

    /// Parse JSON configuration
    fn parse_json(self: *KeyboardConfig, json_text: []const u8) !void {
        // Simple JSON parser for key bindings
        // Format: { "keys": { "F1": "ENTER", "F2": "CLEAR", ... } }

        var iter = std.mem.splitSequence(u8, json_text, "\"");
        var in_keys = false;
        var last_key: ?[]const u8 = null;

        while (iter.next()) |token| {
            const trimmed = std.mem.trim(u8, token, " \t\n\r:");

            if (std.mem.eql(u8, trimmed, "keys")) {
                in_keys = true;
                continue;
            }

            if (!in_keys or trimmed.len == 0) {
                continue;
            }

            // Check if this is a key name or an AID value
            if (last_key == null and !std.mem.containsAtLeast(u8, trimmed, 1, ",")) {
                if (is_valid_key_name(trimmed)) {
                    last_key = trimmed;
                }
            } else if (last_key != null) {
                if (parse_aid_string(trimmed)) |aid| {
                    const key_copy = try self.allocator.dupe(u8, last_key.?);
                    try self.bindings.put(key_copy, aid);
                }
                last_key = null;
            }
        }
    }

    /// Set a key binding
    pub fn set_binding(self: *KeyboardConfig, key: []const u8, aid: protocol.AID) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        try self.bindings.put(key_copy, aid);
    }

    /// Get AID for a key name
    pub fn get_aid(self: KeyboardConfig, key: []const u8) ?protocol.AID {
        return self.bindings.get(key);
    }

    /// Reset to default key bindings
    pub fn load_defaults(self: *KeyboardConfig) !void {
        self.clear();

        try self.set_binding("Enter", protocol.AID.ENTER);
        try self.set_binding("Tab", protocol.AID.TAB);
        try self.set_binding("ShiftTab", protocol.AID.BACKTAB);
        try self.set_binding("Home", protocol.AID.HOME);
        try self.set_binding("Clear", protocol.AID.CLEAR);
        try self.set_binding("Escape", protocol.AID.ESCAPE);
        try self.set_binding("F1", protocol.AID.PF1);
        try self.set_binding("F2", protocol.AID.PF2);
        try self.set_binding("F3", protocol.AID.PF3);
        try self.set_binding("F4", protocol.AID.PF4);
        try self.set_binding("F5", protocol.AID.PF5);
        try self.set_binding("F6", protocol.AID.PF6);
        try self.set_binding("F7", protocol.AID.PF7);
        try self.set_binding("F8", protocol.AID.PF8);
        try self.set_binding("F9", protocol.AID.PF9);
        try self.set_binding("F10", protocol.AID.PF10);
        try self.set_binding("F11", protocol.AID.PF11);
        try self.set_binding("F12", protocol.AID.PF12);
    }

    /// Clear all bindings
    pub fn clear(self: *KeyboardConfig) void {
        var iter = self.bindings.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.bindings.clearRetainingCapacity();
    }

    /// Deinitialize configuration
    pub fn deinit(self: *KeyboardConfig) void {
        self.clear();
        self.bindings.deinit();
    }
};

/// Check if string is a valid key name
fn is_valid_key_name(name: []const u8) bool {
    const valid_keys = [_][]const u8{
        "Enter",  "Tab",    "ShiftTab",  "Home",     "End",
        "Clear",  "Escape", "Backspace", "F1",       "F2",
        "F3",     "F4",     "F5",        "F6",       "F7",
        "F8",     "F9",     "F10",       "F11",      "F12",
        "F13",    "F14",    "F15",       "F16",      "F17",
        "F18",    "F19",    "F20",       "F21",      "F22",
        "F23",    "F24",    "PageUp",    "PageDown", "Insert",
        "Delete", "CtrlJ",  "CtrlK",     "CtrlL",
    };

    for (valid_keys) |key| {
        if (std.mem.eql(u8, name, key)) {
            return true;
        }
    }
    return false;
}

/// Parse AID string to protocol.AID
fn parse_aid_string(name: []const u8) ?protocol.AID {
    // Remove quotes and whitespace
    const clean = std.mem.trim(u8, name, " \t\n\r\"");

    // Try to match AID constants
    if (std.mem.eql(u8, clean, "ENTER")) return protocol.AID.ENTER;
    if (std.mem.eql(u8, clean, "TAB")) return protocol.AID.TAB;
    if (std.mem.eql(u8, clean, "BACKTAB")) return protocol.AID.BACKTAB;
    if (std.mem.eql(u8, clean, "HOME")) return protocol.AID.HOME;
    if (std.mem.eql(u8, clean, "CLEAR")) return protocol.AID.CLEAR;
    if (std.mem.eql(u8, clean, "ESCAPE")) return protocol.AID.ESCAPE;
    if (std.mem.eql(u8, clean, "PF1")) return protocol.AID.PF1;
    if (std.mem.eql(u8, clean, "PF2")) return protocol.AID.PF2;
    if (std.mem.eql(u8, clean, "PF3")) return protocol.AID.PF3;
    if (std.mem.eql(u8, clean, "PF4")) return protocol.AID.PF4;
    if (std.mem.eql(u8, clean, "PF5")) return protocol.AID.PF5;
    if (std.mem.eql(u8, clean, "PF6")) return protocol.AID.PF6;
    if (std.mem.eql(u8, clean, "PF7")) return protocol.AID.PF7;
    if (std.mem.eql(u8, clean, "PF8")) return protocol.AID.PF8;
    if (std.mem.eql(u8, clean, "PF9")) return protocol.AID.PF9;
    if (std.mem.eql(u8, clean, "PF10")) return protocol.AID.PF10;
    if (std.mem.eql(u8, clean, "PF11")) return protocol.AID.PF11;
    if (std.mem.eql(u8, clean, "PF12")) return protocol.AID.PF12;

    return null;
}

// Tests
test "keyboard_config: init creates empty configuration" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 0), config.bindings.count());
}

test "keyboard_config: set_binding stores key mapping" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.set_binding("F1", protocol.AID.ENTER);
    const aid = config.get_aid("F1");

    try std.testing.expectEqual(protocol.AID.ENTER, aid.?);
}

test "keyboard_config: get_aid returns null for unmapped key" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    const aid = config.get_aid("Unmapped");
    try std.testing.expectEqual(@as(?protocol.AID, null), aid);
}

test "keyboard_config: load_defaults sets standard key bindings" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.load_defaults();

    try std.testing.expectEqual(protocol.AID.ENTER, config.get_aid("Enter").?);
    try std.testing.expectEqual(protocol.AID.TAB, config.get_aid("Tab").?);
    try std.testing.expectEqual(protocol.AID.HOME, config.get_aid("Home").?);
    try std.testing.expectEqual(protocol.AID.CLEAR, config.get_aid("Clear").?);
    try std.testing.expectEqual(protocol.AID.PF1, config.get_aid("F1").?);
    try std.testing.expectEqual(protocol.AID.PF12, config.get_aid("F12").?);
}

test "keyboard_config: clear removes all bindings" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.set_binding("F1", protocol.AID.ENTER);
    try config.set_binding("F2", protocol.AID.CLEAR);

    config.clear();

    try std.testing.expectEqual(@as(usize, 0), config.bindings.count());
}

test "keyboard_config: multiple bindings can coexist" {
    var config = KeyboardConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.set_binding("F1", protocol.AID.PF1);
    try config.set_binding("F2", protocol.AID.PF2);
    try config.set_binding("Tab", protocol.AID.TAB);

    try std.testing.expectEqual(@as(usize, 3), config.bindings.count());
    try std.testing.expectEqual(protocol.AID.PF1, config.get_aid("F1").?);
    try std.testing.expectEqual(protocol.AID.PF2, config.get_aid("F2").?);
    try std.testing.expectEqual(protocol.AID.TAB, config.get_aid("Tab").?);
}

test "keyboard_config: load_from_file returns empty config if file missing" {
    const config = try KeyboardConfig.load_from_file(std.testing.allocator, "/nonexistent/path");
    defer config.bindings.deinit();

    try std.testing.expectEqual(@as(usize, 0), config.bindings.count());
}
