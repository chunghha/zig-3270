const std = @import("std");
const attributes = @import("attributes.zig");

/// ANSI color support for 3270 attributes
pub const AnsiColors = struct {
    /// Convert 3270 field attribute to ANSI escape sequence
    pub fn attribute_to_ansi(attr: attributes.FieldAttribute) []const u8 {
        // Default color codes
        if (attr.intensified and attr.protected) {
            return "\x1b[1;90m"; // Bright gray (intensified protected)
        } else if (attr.intensified) {
            return "\x1b[1;37m"; // Bright white (intensified)
        } else if (attr.protected) {
            return "\x1b[2;37m"; // Dim white (protected)
        } else if (attr.hidden) {
            return "\x1b[8m"; // Hidden
        } else if (attr.numeric) {
            return "\x1b[36m"; // Cyan (numeric)
        } else {
            return "\x1b[0m"; // Normal
        }
    }

    /// Get ANSI reset sequence
    pub fn reset() []const u8 {
        return "\x1b[0m";
    }

    /// Wrap text with ANSI color based on attribute
    pub fn wrap_with_attribute(
        allocator: std.mem.Allocator,
        text: []const u8,
        attr: attributes.FieldAttribute,
    ) ![]u8 {
        const ansi_code = attribute_to_ansi(attr);
        const reset_code = reset();

        // Calculate size needed
        const total_size = ansi_code.len + text.len + reset_code.len;
        const result = try allocator.alloc(u8, total_size);

        var idx: usize = 0;

        // Copy ANSI code
        @memcpy(result[idx .. idx + ansi_code.len], ansi_code);
        idx += ansi_code.len;

        // Copy text
        @memcpy(result[idx .. idx + text.len], text);
        idx += text.len;

        // Copy reset code
        @memcpy(result[idx .. idx + reset_code.len], reset_code);

        return result;
    }

    /// Map 3270 field attributes to standard terminal colors
    pub fn get_color_pair(attr: attributes.FieldAttribute) struct { fg: u8, bg: u8, bold: bool } {
        // Standard ANSI colors
        // 0=black, 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white
        if (attr.intensified and attr.protected) {
            return .{ .fg = 8, .bg = 0, .bold = true }; // Bright default
        } else if (attr.intensified) {
            return .{ .fg = 7, .bg = 0, .bold = true }; // Bright white
        } else if (attr.protected) {
            return .{ .fg = 4, .bg = 0, .bold = false }; // Blue (protected fields)
        } else if (attr.hidden) {
            return .{ .fg = 0, .bg = 0, .bold = false }; // Black on black (hidden)
        } else if (attr.numeric) {
            return .{ .fg = 6, .bg = 0, .bold = false }; // Cyan (numeric fields)
        } else {
            return .{ .fg = 7, .bg = 0, .bold = false }; // Default white
        }
    }

    /// Create ANSI SGR (Select Graphic Rendition) sequence
    pub fn create_sgr_sequence(
        allocator: std.mem.Allocator,
        fg_color: u8,
        bg_color: u8,
        bold: bool,
    ) ![]u8 {
        var buffer: [32]u8 = undefined;
        var idx: usize = 0;

        // ESC [
        buffer[idx] = 0x1b;
        idx += 1;
        buffer[idx] = '[';
        idx += 1;

        // Bold
        if (bold) {
            buffer[idx] = '1';
            idx += 1;
            buffer[idx] = ';';
            idx += 1;
        }

        // Foreground color (30-37)
        idx += std.fmt.bufPrintZ(buffer[idx..], "3{d}", .{fg_color}) catch return error.BufferOverflow;
        buffer[idx] = ';';
        idx += 1;

        // Background color (40-47)
        idx += std.fmt.bufPrintZ(buffer[idx..], "4{d}", .{bg_color}) catch return error.BufferOverflow;
        buffer[idx] = 'm';
        idx += 1;

        return allocator.dupe(u8, buffer[0..idx]);
    }
};

// Tests
test "ansi_colors: normal attribute returns reset" {
    var normal_attr: attributes.FieldAttribute = undefined;
    normal_attr.intensified = false;
    normal_attr.protected = false;
    normal_attr.hidden = false;
    normal_attr.numeric = false;

    const code = AnsiColors.attribute_to_ansi(normal_attr);
    try std.testing.expectEqualSlices(u8, "\x1b[0m", code);
}

test "ansi_colors: intensified attribute uses bright white" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = true;
    attr.protected = false;
    attr.hidden = false;
    attr.numeric = false;

    const code = AnsiColors.attribute_to_ansi(attr);
    try std.testing.expectEqualSlices(u8, "\x1b[1;37m", code);
}

test "ansi_colors: protected attribute uses dim white" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = false;
    attr.protected = true;
    attr.hidden = false;
    attr.numeric = false;

    const code = AnsiColors.attribute_to_ansi(attr);
    try std.testing.expectEqualSlices(u8, "\x1b[2;37m", code);
}

test "ansi_colors: hidden attribute uses hidden escape" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = false;
    attr.protected = false;
    attr.hidden = true;
    attr.numeric = false;

    const code = AnsiColors.attribute_to_ansi(attr);
    try std.testing.expectEqualSlices(u8, "\x1b[8m", code);
}

test "ansi_colors: numeric attribute uses cyan" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = false;
    attr.protected = false;
    attr.hidden = false;
    attr.numeric = true;

    const code = AnsiColors.attribute_to_ansi(attr);
    try std.testing.expectEqualSlices(u8, "\x1b[36m", code);
}

test "ansi_colors: wrap_with_attribute wraps text correctly" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = true;
    attr.protected = false;
    attr.hidden = false;
    attr.numeric = false;

    const wrapped = try AnsiColors.wrap_with_attribute(
        std.testing.allocator,
        "TEST",
        attr,
    );
    defer std.testing.allocator.free(wrapped);

    try std.testing.expectEqualSlices(u8, "\x1b[1;37mTEST\x1b[0m", wrapped);
}

test "ansi_colors: get_color_pair returns correct colors for intensified" {
    var attr: attributes.FieldAttribute = undefined;
    attr.intensified = true;
    attr.protected = false;
    attr.hidden = false;
    attr.numeric = false;

    const colors = AnsiColors.get_color_pair(attr);
    try std.testing.expectEqual(@as(u8, 7), colors.fg);
    try std.testing.expectEqual(@as(u8, 0), colors.bg);
    try std.testing.expect(colors.bold);
}

test "ansi_colors: reset returns proper code" {
    const reset = AnsiColors.reset();
    try std.testing.expectEqualSlices(u8, "\x1b[0m", reset);
}

test "ansi_colors: create_sgr_sequence builds valid sequence" {
    const seq = try AnsiColors.create_sgr_sequence(
        std.testing.allocator,
        7,
        0,
        true,
    );
    defer std.testing.allocator.free(seq);

    // Should contain ESC [ and end with 'm'
    try std.testing.expectEqual(@as(u8, 0x1b), seq[0]);
    try std.testing.expectEqual(@as(u8, '['), seq[1]);
    try std.testing.expectEqual(@as(u8, 'm'), seq[seq.len - 1]);
}
