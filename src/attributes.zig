const std = @import("std");
const protocol = @import("protocol.zig");

/// ANSI color codes for 3270 attributes
pub const AnsiColor = struct {
    foreground: []const u8,
    background: []const u8,
    bright: bool,
    reverse: bool,

    pub fn code(self: AnsiColor) [32]u8 {
        var buf: [32]u8 = undefined;
        var pos: usize = 0;

        // Build ANSI sequence
        buf[pos] = 0x1B;
        pos += 1;
        buf[pos] = '[';
        pos += 1;

        if (self.bright) {
            @memcpy(buf[pos .. pos + 1], "1");
            pos += 1;
            buf[pos] = ';';
            pos += 1;
        }

        if (self.reverse) {
            @memcpy(buf[pos .. pos + 1], "7");
            pos += 1;
            buf[pos] = ';';
            pos += 1;
        }

        @memcpy(buf[pos .. pos + self.foreground.len], self.foreground);
        pos += self.foreground.len;

        buf[pos] = ';';
        pos += 1;

        @memcpy(buf[pos .. pos + self.background.len], self.background);
        pos += self.background.len;

        buf[pos] = 'm';
        pos += 1;

        // Pad with nulls
        while (pos < buf.len) : (pos += 1) {
            buf[pos] = 0;
        }

        return buf;
    }
};

/// Attribute renderer - converts 3270 field attributes to ANSI styling
pub const AttributeRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AttributeRenderer {
        return AttributeRenderer{
            .allocator = allocator,
        };
    }

    /// Convert field attribute to ANSI color codes
    pub fn attribute_to_color(self: *AttributeRenderer, attr: protocol.FieldAttribute) !AnsiColor {
        _ = self;

        var color: AnsiColor = .{
            .foreground = "37", // Default white
            .background = "40", // Default black
            .bright = false,
            .reverse = false,
        };

        // Protected fields: dim or reverse
        if (attr.protected) {
            color.reverse = true;
        }

        // Intensified: bright
        if (attr.intensified) {
            color.bright = true;
            color.foreground = "1;37"; // Bright white
        }

        // Hidden: black on black
        if (attr.hidden) {
            color.foreground = "30"; // Black
            color.background = "40"; // Black
        }

        // Numeric: right-aligned (indicator only, layout is app's job)
        if (attr.numeric) {
            color.bright = true;
        }

        return color;
    }

    /// Get ANSI reset code
    pub fn reset_code(self: *AttributeRenderer) []const u8 {
        _ = self;
        return "\x1B[0m";
    }
};

test "attribute renderer protected field" {
    var ar = AttributeRenderer.init(std.testing.allocator);

    const attr = protocol.FieldAttribute{ .protected = true };
    const color = try ar.attribute_to_color(attr);

    try std.testing.expect(color.reverse);
}

test "attribute renderer intensified field" {
    var ar = AttributeRenderer.init(std.testing.allocator);

    const attr = protocol.FieldAttribute{ .intensified = true };
    const color = try ar.attribute_to_color(attr);

    try std.testing.expect(color.bright);
}

test "attribute renderer hidden field" {
    var ar = AttributeRenderer.init(std.testing.allocator);

    const attr = protocol.FieldAttribute{ .hidden = true };
    const color = try ar.attribute_to_color(attr);

    try std.testing.expectEqualStrings("30", color.foreground);
    try std.testing.expectEqualStrings("40", color.background);
}

test "attribute renderer numeric field" {
    var ar = AttributeRenderer.init(std.testing.allocator);

    const attr = protocol.FieldAttribute{ .numeric = true };
    const color = try ar.attribute_to_color(attr);

    try std.testing.expect(color.bright);
}

test "attribute renderer reset code" {
    var ar = AttributeRenderer.init(std.testing.allocator);
    const reset = ar.reset_code();

    try std.testing.expectEqualStrings("\x1B[0m", reset);
}
