const std = @import("std");
const screen = @import("screen.zig");
const field = @import("field.zig");
const protocol = @import("protocol.zig");

/// Inspects and exports emulator state for debugging
pub const StateInspector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StateInspector {
        return StateInspector{
            .allocator = allocator,
        };
    }

    /// Dump screen state as human-readable text
    pub fn dump_screen_state(
        self: StateInspector,
        screen_buffer: *const screen.ScreenBuffer,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== SCREEN STATE ===\n", .{});
        try writer.print("Dimensions: {}x{}\n", .{ screen_buffer.rows, screen_buffer.cols });
        try writer.print("Total cells: {}\n\n", .{screen_buffer.buffer.len});

        // Write screen contents
        try writer.print("Screen Contents:\n", .{});
        for (0..screen_buffer.rows) |row| {
            try writer.print("[{:2}] ", .{row});
            for (0..screen_buffer.cols) |col| {
                const idx = row * screen_buffer.cols + col;
                if (idx < screen_buffer.buffer.len) {
                    const ch = screen_buffer.buffer[idx];
                    if (ch >= 32 and ch < 127) {
                        try writer.print("{c}", .{@as(u8, ch)});
                    } else {
                        try writer.print(".", .{});
                    }
                }
            }
            try writer.print("\n", .{});
        }

        return result.toOwnedSlice();
    }

    /// Dump field state as human-readable text
    pub fn dump_field_state(
        self: StateInspector,
        field_manager: *const field.FieldManager,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== FIELD STATE ===\n", .{});
        try writer.print("Total fields: {}\n\n", .{field_manager.fields.len});

        for (field_manager.fields, 0..) |fld, idx| {
            try writer.print("Field {}: ", .{idx});
            try writer.print("({},{}) ", .{ fld.start_address.row, fld.start_address.col });
            try writer.print("len={} ", .{fld.length});

            const attr = fld.attribute;
            var attr_strs = std.ArrayList([]const u8).init(self.allocator);
            defer {
                for (attr_strs.items) |s| {
                    self.allocator.free(s);
                }
                attr_strs.deinit();
            }

            if (attr.protected) {
                try attr_strs.append(try self.allocator.dupe(u8, "protected"));
            }
            if (attr.numeric) {
                try attr_strs.append(try self.allocator.dupe(u8, "numeric"));
            }
            if (attr.hidden) {
                try attr_strs.append(try self.allocator.dupe(u8, "hidden"));
            }
            if (attr.intensified) {
                try attr_strs.append(try self.allocator.dupe(u8, "intensified"));
            }
            if (attr.modified) {
                try attr_strs.append(try self.allocator.dupe(u8, "modified"));
            }

            if (attr_strs.items.len > 0) {
                try writer.print("attrs=[", .{});
                for (attr_strs.items, 0..) |a, i| {
                    if (i > 0) try writer.print(",", .{});
                    try writer.print("{s}", .{a});
                }
                try writer.print("]", .{});
            }
            try writer.print("\n", .{});
        }

        return result.toOwnedSlice();
    }

    /// Dump keyboard state
    pub fn dump_keyboard_state(
        self: StateInspector,
        locked: bool,
        last_key: ?u8,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== KEYBOARD STATE ===\n", .{});
        try writer.print("Locked: {}\n", .{locked});
        if (last_key) |key| {
            if (key >= 32 and key < 127) {
                try writer.print("Last Key: '{}' (0x{x:02})\n", .{ @as(u8, key), key });
            } else {
                try writer.print("Last Key: 0x{x:02}\n", .{key});
            }
        } else {
            try writer.print("Last Key: none\n", .{});
        }

        return result.toOwnedSlice();
    }

    /// Export complete state as JSON
    pub fn export_to_json(
        self: StateInspector,
        screen_buffer: *const screen.ScreenBuffer,
        field_manager: *const field.FieldManager,
        keyboard_locked: bool,
        last_key: ?u8,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("{{\n", .{});

        // Screen section
        try writer.print("  \"screen\": {{\n", .{});
        try writer.print("    \"rows\": {},\n", .{screen_buffer.rows});
        try writer.print("    \"cols\": {},\n", .{screen_buffer.cols});
        try writer.print("    \"buffer\": [", .{});

        for (screen_buffer.buffer, 0..) |byte, i| {
            if (i > 0 and i % 20 == 0) {
                try writer.print("\n      ", .{});
            } else if (i > 0) {
                try writer.print(" ", .{});
            }
            try writer.print("{}", .{byte});
            if (i < screen_buffer.buffer.len - 1) {
                try writer.print(",", .{});
            }
        }
        try writer.print("]\n", .{});
        try writer.print("  }},\n", .{});

        // Fields section
        try writer.print("  \"fields\": [\n", .{});
        for (field_manager.fields, 0..) |fld, idx| {
            if (idx > 0) try writer.print(",\n", .{});
            try writer.print("    {{\n", .{});
            try writer.print("      \"index\": {},\n", .{idx});
            try writer.print("      \"start_row\": {},\n", .{fld.start_address.row});
            try writer.print("      \"start_col\": {},\n", .{fld.start_address.col});
            try writer.print("      \"length\": {},\n", .{fld.length});
            try writer.print("      \"protected\": {},\n", .{fld.attribute.protected});
            try writer.print("      \"numeric\": {},\n", .{fld.attribute.numeric});
            try writer.print("      \"hidden\": {},\n", .{fld.attribute.hidden});
            try writer.print("      \"intensified\": {},\n", .{fld.attribute.intensified});
            try writer.print("      \"modified\": {}\n", .{fld.attribute.modified});
            try writer.print("    }}", .{});
        }
        try writer.print("\n  ],\n", .{});

        // Keyboard section
        try writer.print("  \"keyboard\": {{\n", .{});
        try writer.print("    \"locked\": {}", .{keyboard_locked});
        if (last_key) |key| {
            try writer.print(",\n    \"last_key\": {}", .{key});
        }
        try writer.print("\n  }}\n", .{});

        try writer.print("}}\n", .{});

        return result.toOwnedSlice();
    }
};

// Tests
test "state inspector: dump screen state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sb = try screen.ScreenBuffer.init(allocator, 24, 80);
    defer sb.deinit();

    sb.buffer[0] = 'H';
    sb.buffer[1] = 'i';

    const inspector = StateInspector.init(allocator);
    const dump = try inspector.dump_screen_state(&sb);
    defer allocator.free(dump);

    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "SCREEN STATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "24x80"));
}

test "state inspector: dump field state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fm = field.FieldManager.init(allocator);
    defer fm.deinit();

    const fld = field.Field{
        .start_address = protocol.Address{ .row = 0, .col = 0 },
        .length = 10,
        .attribute = protocol.FieldAttribute{ .protected = true },
    };
    try fm.add_field(fld);

    const inspector = StateInspector.init(allocator);
    const dump = try inspector.dump_field_state(&fm);
    defer allocator.free(dump);

    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "FIELD STATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "protected"));
}

test "state inspector: dump keyboard state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const inspector = StateInspector.init(allocator);
    const dump = try inspector.dump_keyboard_state(true, 'A');
    defer allocator.free(dump);

    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "KEYBOARD STATE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, dump, 1, "Locked: true"));
}

test "state inspector: export to json" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sb = try screen.ScreenBuffer.init(allocator, 24, 80);
    defer sb.deinit();

    var fm = field.FieldManager.init(allocator);
    defer fm.deinit();

    const inspector = StateInspector.init(allocator);
    const json = try inspector.export_to_json(&sb, &fm, false, null);
    defer allocator.free(json);

    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"screen\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"fields\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"keyboard\""));
}
