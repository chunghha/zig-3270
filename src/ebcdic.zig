const std = @import("std");

/// EBCDIC (Extended Binary Coded Decimal Interchange Code)
/// Standard encoding used by IBM mainframes and TN3270 protocol
pub const Ebcdic = struct {
    /// EBCDIC to ASCII lookup table
    /// Maps EBCDIC byte (0-255) to ASCII character
    const ebcdic_to_ascii_table = [256]u8{
        // 0x00-0x0F
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        // 0x10-0x1F
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
        // 0x20-0x2F
        0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
        0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
        // 0x30-0x3F
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
        // 0x40: space in EBCDIC
        0x20,
        // 0x41-0x49: EBCDIC for A-I
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
        0x48, 0x49,
        // 0x4A-0x4F
        0x5B, 0x2E, 0x3C, 0x28, 0x2B, 0x21,
        // 0x50-0x59: EBCDIC for J-R
        0x26, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50,
        0x51, 0x52,
        // 0x5A-0x5F
        0x5D, 0x24, 0x2A, 0x29, 0x3B, 0x5E,
        // 0x60-0x69: EBCDIC for S-Z
        0x2D, 0x2F, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A,
        // 0x6A-0x6F
        0x3F, 0x2C, 0x25, 0x5F, 0x3E, 0x3F,
        // 0x70-0x79: EBCDIC for 0-9
        0x60, 0x3A, 0x23, 0x40, 0x27, 0x3D, 0x22, 0x7E,
        0x7C, 0x7B,
        // 0x7A-0x7F
        0x7D, 0x7B, 0x7D, 0x7E, 0x7F, 0x7F,
        // 0x80-0x8F (control characters)
        0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
        // 0x90-0x9F (control characters)
        0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
        0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
        // 0xA0-0xAF
        0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF,
        // 0xB0-0xBF
        0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7,
        0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF,
        // 0xC0-0xCF (EBCDIC for a-i and remaining chars)
        0x7B, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67,
        0x68, 0x69, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF,
        // 0xD0-0xDF (EBCDIC for j-r and remaining chars)
        0x7D, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70,
        0x71, 0x72, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF,
        // 0xE0-0xEF (EBCDIC for s-z and remaining chars)
        0x5C, 0xE1, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
        0x79, 0x7A, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF,
        // 0xF0-0xFF (EBCDIC for 0-9 extended)
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF,
    };

    /// ASCII to EBCDIC lookup table
    /// Maps ASCII byte (0-127) to EBCDIC character
    const ascii_to_ebcdic_table = [128]u8{
        // 0x00-0x0F (control characters pass through)
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        // 0x10-0x1F (control characters pass through)
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
        // 0x20: space
        0x40,
        // 0x21: !
        0x4F,
        // 0x22: "
        0x7F,
        // 0x23: #
        0x7B,
        // 0x24: $
        0x5B,
        // 0x25: %
        0x6C,
        // 0x26: &
        0x50,
        // 0x27: '
        0x7D,
        // 0x28: (
        0x4D,
        // 0x29: )
        0x5D,
        // 0x2A: *
        0x5C,
        // 0x2B: +
        0x4E,
        // 0x2C: ,
        0x6B,
        // 0x2D: -
        0x60,
        // 0x2E: .
        0x4B,
        // 0x2F: /
        0x61,
        // 0x30-0x39: digits 0-9
        0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7,
        0xF8, 0xF9,
        // 0x3A: :
        0x7A,
        // 0x3B: ;
        0x5E,
        // 0x3C: <
        0x4C,
        // 0x3D: =
        0x7E,
        // 0x3E: >
        0x6E,
        // 0x3F: ?
        0x6F,
        // 0x40: @
        0x7C,
        // 0x41-0x49: A-I
        0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,
        0xC8, 0xC9,
        // 0x4A-0x52: J-R
        0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
        0xD7, 0xD8, 0xD9,
        // 0x53-0x5A: S-Z
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6,
        0xE7, 0xE8, 0xE9,
        // 0x5B: [
        0x4A,
        // 0x5C: backslash
        0xE0,
        // 0x5D: ]
        0x5A,
        // 0x5E: ^
        0x5F,
        // 0x5F: _
        0x6D,
        // 0x60: backtick
        0x79,
        // 0x61-0x69: a-i
        0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89,
        // 0x6A-0x72: j-r
        0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
        0x97, 0x98, 0x99,
        // 0x73-0x7A: s-z
        0xA2, 0xA3, 0xA4, 0xA5, 0xA6,
        0xA7, 0xA8, 0xA9,
        // 0x7B: {
        0xC0,
        // 0x7C: |
        0x6A,
        // 0x7D: }
        0xD0,
        // 0x7E: ~
        0xA1,
        // 0x7F: DEL
        0x07,
    };

    /// Decode EBCDIC byte to ASCII
    pub fn decode_byte(ebcdic_byte: u8) u8 {
        return ebcdic_to_ascii_table[ebcdic_byte];
    }

    /// Encode ASCII byte to EBCDIC
    /// Returns error for ASCII values > 127
    pub fn encode_byte(ascii_byte: u8) !u8 {
        if (ascii_byte > 127) {
            return error.InvalidAsciiValue;
        }
        return ascii_to_ebcdic_table[ascii_byte];
    }

    /// Decode EBCDIC buffer to ASCII
    pub fn decode(ebcdic_buffer: []const u8, ascii_buffer: []u8) !usize {
        if (ascii_buffer.len < ebcdic_buffer.len) {
            return error.BufferTooSmall;
        }

        for (ebcdic_buffer, 0..) |byte, i| {
            ascii_buffer[i] = decode_byte(byte);
        }

        return ebcdic_buffer.len;
    }

    /// Encode ASCII buffer to EBCDIC
    pub fn encode(ascii_buffer: []const u8, ebcdic_buffer: []u8) !usize {
        if (ebcdic_buffer.len < ascii_buffer.len) {
            return error.BufferTooSmall;
        }

        for (ascii_buffer, 0..) |byte, i| {
            ebcdic_buffer[i] = try encode_byte(byte);
        }

        return ascii_buffer.len;
    }

    /// Allocate and return decoded ASCII string
    pub fn decode_alloc(allocator: std.mem.Allocator, ebcdic_buffer: []const u8) ![]u8 {
        const result = try allocator.alloc(u8, ebcdic_buffer.len);
        errdefer allocator.free(result);
        _ = try decode(ebcdic_buffer, result);
        return result;
    }

    /// Allocate and return encoded EBCDIC buffer
    pub fn encode_alloc(allocator: std.mem.Allocator, ascii_buffer: []const u8) ![]u8 {
        const result = try allocator.alloc(u8, ascii_buffer.len);
        errdefer allocator.free(result);
        _ = try encode(ascii_buffer, result);
        return result;
    }
};

// Tests
test "ebcdic decode byte space" {
    const decoded = Ebcdic.decode_byte(0x40); // EBCDIC space
    try std.testing.expectEqual(@as(u8, 0x20), decoded); // ASCII space
}

test "ebcdic decode byte A" {
    const decoded = Ebcdic.decode_byte(0xC1); // EBCDIC A
    try std.testing.expectEqual(@as(u8, 0x41), decoded); // ASCII A
}

test "ebcdic decode byte 0" {
    const decoded = Ebcdic.decode_byte(0xF0); // EBCDIC 0
    try std.testing.expectEqual(@as(u8, 0x30), decoded); // ASCII 0
}

test "ebcdic encode byte space" {
    const encoded = try Ebcdic.encode_byte(0x20); // ASCII space
    try std.testing.expectEqual(@as(u8, 0x40), encoded); // EBCDIC space
}

test "ebcdic encode byte A" {
    const encoded = try Ebcdic.encode_byte(0x41); // ASCII A
    try std.testing.expectEqual(@as(u8, 0xC1), encoded); // EBCDIC A
}

test "ebcdic encode byte 0" {
    const encoded = try Ebcdic.encode_byte(0x30); // ASCII 0
    try std.testing.expectEqual(@as(u8, 0xF0), encoded); // EBCDIC 0
}

test "ebcdic encode byte invalid" {
    const result = Ebcdic.encode_byte(0xFF);
    try std.testing.expectError(error.InvalidAsciiValue, result);
}

test "ebcdic decode buffer" {
    const ebcdic = &.{ 0xC1, 0xC2, 0xC3 }; // EBCDIC ABC
    var ascii: [3]u8 = undefined;
    const len = try Ebcdic.decode(ebcdic, &ascii);
    try std.testing.expectEqual(@as(usize, 3), len);
    try std.testing.expectEqualSlices(u8, "ABC", &ascii);
}

test "ebcdic encode buffer" {
    const ascii = "ABC";
    var ebcdic: [3]u8 = undefined;
    const len = try Ebcdic.encode(ascii, &ebcdic);
    try std.testing.expectEqual(@as(usize, 3), len);
    try std.testing.expectEqual(@as(u8, 0xC1), ebcdic[0]);
    try std.testing.expectEqual(@as(u8, 0xC2), ebcdic[1]);
    try std.testing.expectEqual(@as(u8, 0xC3), ebcdic[2]);
}

test "ebcdic decode buffer too small" {
    const ebcdic = &.{ 0xC1, 0xC2, 0xC3 };
    var ascii: [2]u8 = undefined;
    const result = Ebcdic.decode(ebcdic, &ascii);
    try std.testing.expectError(error.BufferTooSmall, result);
}

test "ebcdic encode buffer too small" {
    const ascii = "ABC";
    var ebcdic: [2]u8 = undefined;
    const result = Ebcdic.encode(ascii, &ebcdic);
    try std.testing.expectError(error.BufferTooSmall, result);
}

test "ebcdic encode buffer with invalid char" {
    const ascii = &.{ 0x41, 0xFF }; // A followed by invalid byte
    var ebcdic: [2]u8 = undefined;
    const result = Ebcdic.encode(ascii, &ebcdic);
    try std.testing.expectError(error.InvalidAsciiValue, result);
}

test "ebcdic decode alloc" {
    const ebcdic = &.{ 0xC1, 0xC2, 0xC3 };
    const ascii = try Ebcdic.decode_alloc(std.testing.allocator, ebcdic);
    defer std.testing.allocator.free(ascii);
    try std.testing.expectEqualSlices(u8, "ABC", ascii);
}

test "ebcdic encode alloc" {
    const ascii = "ABC";
    const ebcdic = try Ebcdic.encode_alloc(std.testing.allocator, ascii);
    defer std.testing.allocator.free(ebcdic);
    try std.testing.expectEqual(@as(u8, 0xC1), ebcdic[0]);
    try std.testing.expectEqual(@as(u8, 0xC2), ebcdic[1]);
    try std.testing.expectEqual(@as(u8, 0xC3), ebcdic[2]);
}

test "ebcdic round trip encode then decode" {
    const original = "HELLO123";
    var encoded: [8]u8 = undefined;
    var decoded: [8]u8 = undefined;

    _ = try Ebcdic.encode(original, &encoded);
    _ = try Ebcdic.decode(&encoded, &decoded);

    try std.testing.expectEqualSlices(u8, original, &decoded);
}

test "ebcdic special characters" {
    const special = "!@#$%";
    var encoded: [5]u8 = undefined;
    var decoded: [5]u8 = undefined;

    _ = try Ebcdic.encode(special, &encoded);
    _ = try Ebcdic.decode(&encoded, &decoded);

    try std.testing.expectEqualSlices(u8, special, &decoded);
}

test "ebcdic digits round trip" {
    const digits = "0123456789";
    var encoded: [10]u8 = undefined;
    var decoded: [10]u8 = undefined;

    _ = try Ebcdic.encode(digits, &encoded);
    _ = try Ebcdic.decode(&encoded, &decoded);

    try std.testing.expectEqualSlices(u8, digits, &decoded);
}

test "ebcdic lowercase round trip" {
    const lowercase = "abcxyz";
    var encoded: [6]u8 = undefined;
    var decoded: [6]u8 = undefined;

    _ = try Ebcdic.encode(lowercase, &encoded);
    _ = try Ebcdic.decode(&encoded, &decoded);

    try std.testing.expectEqualSlices(u8, lowercase, &decoded);
}
