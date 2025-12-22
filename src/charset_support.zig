const std = @import("std");

/// Character set support for TN3270
/// Supports APL and extended Latin-1 character sets
pub const CharacterSet = enum {
    ascii, // Standard ASCII
    latin1, // Extended Latin-1 (ISO-8859-1)
    apl, // APL character set
    ebcdic, // EBCDIC
};

/// APL character mappings
/// Maps ASCII values to APL unicode representations
pub const AplCharacter = struct {
    ascii_code: u8,
    apl_symbol: []const u8, // Unicode string
    apl_name: []const u8,
};

const apl_mappings = [_]AplCharacter{
    .{ .ascii_code = 33, .apl_symbol = "⍳", .apl_name = "iota" },
    .{ .ascii_code = 34, .apl_symbol = "¨", .apl_name = "diaeresis" },
    .{ .ascii_code = 35, .apl_symbol = "⍒", .apl_name = "grade down" },
    .{ .ascii_code = 36, .apl_symbol = "⍋", .apl_name = "grade up" },
    .{ .ascii_code = 37, .apl_symbol = "∣", .apl_name = "absolute value" },
    .{ .ascii_code = 38, .apl_symbol = "∧", .apl_name = "and" },
    .{ .ascii_code = 39, .apl_symbol = "⍪", .apl_name = "table" },
    .{ .ascii_code = 40, .apl_symbol = "⊂", .apl_name = "enclose" },
    .{ .ascii_code = 41, .apl_symbol = "⊃", .apl_name = "disclose" },
    .{ .ascii_code = 42, .apl_symbol = "⋆", .apl_name = "star" },
    .{ .ascii_code = 43, .apl_symbol = "⌈", .apl_name = "ceiling" },
    .{ .ascii_code = 44, .apl_symbol = "⌊", .apl_name = "floor" },
    .{ .ascii_code = 45, .apl_symbol = "~", .apl_name = "not" },
    .{ .ascii_code = 47, .apl_symbol = "÷", .apl_name = "divide" },
    .{ .ascii_code = 59, .apl_symbol = "⍰", .apl_name = "query" },
    .{ .ascii_code = 60, .apl_symbol = "⍲", .apl_name = "nand" },
    .{ .ascii_code = 61, .apl_symbol = "≤", .apl_name = "less or equal" },
    .{ .ascii_code = 62, .apl_symbol = "≥", .apl_name = "greater or equal" },
    .{ .ascii_code = 94, .apl_symbol = "⌽", .apl_name = "reverse" },
    .{ .ascii_code = 126, .apl_symbol = "⍟", .apl_name = "log" },
};

const latin1_mappings = [_]struct {
    code: u8,
    name: []const u8,
}{
    .{ .code = 160, .name = "non-breaking space" },
    .{ .code = 161, .name = "inverted exclamation" },
    .{ .code = 162, .name = "cent sign" },
    .{ .code = 163, .name = "pound sign" },
    .{ .code = 164, .name = "currency sign" },
    .{ .code = 165, .name = "yen sign" },
    .{ .code = 166, .name = "broken bar" },
    .{ .code = 167, .name = "section sign" },
    .{ .code = 168, .name = "diaeresis" },
    .{ .code = 169, .name = "copyright" },
    .{ .code = 170, .name = "feminine ordinal" },
    .{ .code = 171, .name = "left guillemet" },
    .{ .code = 172, .name = "not sign" },
    .{ .code = 173, .name = "soft hyphen" },
    .{ .code = 174, .name = "registered" },
    .{ .code = 175, .name = "macron" },
};

/// Character set converter
pub const CharsetConverter = struct {
    allocator: std.mem.Allocator,
    source_set: CharacterSet,
    target_set: CharacterSet,
    error_mode: ErrorMode = .replace,

    pub const ErrorMode = enum {
        replace, // Replace unknown with '?'
        skip, // Skip unknown characters
        error_mode, // Return error
    };

    pub fn init(
        allocator: std.mem.Allocator,
        source: CharacterSet,
        target: CharacterSet,
    ) CharsetConverter {
        return CharsetConverter{
            .allocator = allocator,
            .source_set = source,
            .target_set = target,
        };
    }

    /// Convert buffer from source to target charset
    pub fn convert(self: CharsetConverter, input: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        for (input) |byte| {
            const converted = try self.convert_byte(byte);
            if (converted.len > 0) {
                try output.appendSlice(converted);
            }
        }

        return output.toOwnedSlice();
    }

    /// Convert single byte
    pub fn convert_byte(self: CharsetConverter, input: u8) ![]const u8 {
        // No conversion needed for same charset
        if (self.source_set == self.target_set) {
            return &.{input};
        }

        return switch (self.source_set) {
            .ascii => switch (self.target_set) {
                .apl => try self.ascii_to_apl(input),
                .latin1 => if (input < 128) &.{input} else return self.handle_unknown_char(),
                .ebcdic => return error.EbcdcConversionNotSupported,
                else => &.{input},
            },
            .latin1 => switch (self.target_set) {
                .apl => try self.latin1_to_apl(input),
                .ascii => if (input < 128) &.{input} else return self.handle_unknown_char(),
                .ebcdic => return error.EbcdcConversionNotSupported,
                else => &.{input},
            },
            .apl => switch (self.target_set) {
                .ascii => try self.apl_to_ascii(input),
                .latin1 => try self.apl_to_latin1(input),
                else => &.{input},
            },
            else => &.{input},
        };
    }

    fn ascii_to_apl(self: CharsetConverter, code: u8) ![]const u8 {
        for (apl_mappings) |mapping| {
            if (mapping.ascii_code == code) {
                return mapping.apl_symbol;
            }
        }
        return self.handle_unknown_char();
    }

    fn latin1_to_apl(self: CharsetConverter, code: u8) ![]const u8 {
        // For now, just convert ASCII portion
        if (code < 128) {
            return try self.ascii_to_apl(code);
        }
        return self.handle_unknown_char();
    }

    fn apl_to_ascii(self: CharsetConverter, _: u8) ![]const u8 {
        // Simplified: just return '?'
        return self.handle_unknown_char();
    }

    fn apl_to_latin1(self: CharsetConverter, _: u8) ![]const u8 {
        return self.handle_unknown_char();
    }

    fn handle_unknown_char(self: CharsetConverter) ![]const u8 {
        return switch (self.error_mode) {
            .replace => "?",
            .skip => "",
            .error_mode => error.UnknownCharacter,
        };
    }
};

/// Get character set name
pub fn getCharsetName(charset: CharacterSet) []const u8 {
    return switch (charset) {
        .ascii => "ASCII",
        .latin1 => "Latin-1 (ISO-8859-1)",
        .apl => "APL",
        .ebcdic => "EBCDIC",
    };
}

/// Check if character set is supported
pub fn isSupported(charset: CharacterSet) bool {
    return switch (charset) {
        .ascii, .latin1, .apl => true,
        .ebcdic => true, // Supported via ebcdic.zig
    };
}

/// Get APL symbol for character code
pub fn getAplSymbol(ascii_code: u8) ?[]const u8 {
    for (apl_mappings) |mapping| {
        if (mapping.ascii_code == ascii_code) {
            return mapping.apl_symbol;
        }
    }
    return null;
}

/// Get APL character name
pub fn getAplName(ascii_code: u8) ?[]const u8 {
    for (apl_mappings) |mapping| {
        if (mapping.ascii_code == ascii_code) {
            return mapping.apl_name;
        }
    }
    return null;
}

// Tests
test "charset: get charset name" {
    try std.testing.expectEqualStrings("ASCII", getCharsetName(.ascii));
    try std.testing.expectEqualStrings("APL", getCharsetName(.apl));
}

test "charset: is supported" {
    try std.testing.expect(isSupported(.ascii));
    try std.testing.expect(isSupported(.latin1));
    try std.testing.expect(isSupported(.apl));
}

test "charset: get apl symbol" {
    const symbol = getAplSymbol(33); // Should be iota
    try std.testing.expect(symbol != null);
}

test "charset: get apl name" {
    const name = getAplName(33); // Should be "iota"
    try std.testing.expect(name != null);
    if (name) |n| {
        try std.testing.expectEqualStrings("iota", n);
    }
}

test "charset converter: no conversion needed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const converter = CharsetConverter.init(allocator, .ascii, .ascii);
    const result = try converter.convert_byte('A');

    try std.testing.expectEqualStrings("A", result);
}

test "charset converter: ascii to apl" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const converter = CharsetConverter.init(allocator, .ascii, .apl);
    const result = try converter.convert_byte('!');

    try std.testing.expect(result.len > 0);
}

test "charset converter: unknown character handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var converter = CharsetConverter.init(allocator, .ascii, .latin1);
    converter.error_mode = .replace;

    const result = try converter.convert_byte(200);
    try std.testing.expectEqualStrings("?", result);
}
