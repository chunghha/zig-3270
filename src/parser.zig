const std = @import("std");
const protocol = @import("protocol.zig");

/// 3270 command buffer parsing
pub const Parser = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    position: usize,

    /// Initialize parser with a buffer
    pub fn init(allocator: std.mem.Allocator, buffer: []u8) Parser {
        return Parser{
            .allocator = allocator,
            .buffer = buffer,
            .position = 0,
        };
    }

    /// Peek next byte without advancing position
    pub fn peek(self: *Parser) !u8 {
        if (self.position >= self.buffer.len) {
            return error.EndOfBuffer;
        }
        return self.buffer[self.position];
    }

    /// Read next byte and advance position
    pub fn read(self: *Parser) !u8 {
        const byte = try self.peek();
        self.position += 1;
        return byte;
    }

    /// Read N bytes into a buffer
    pub fn read_bytes(self: *Parser, n: usize) ![]u8 {
        if (self.position + n > self.buffer.len) {
            return error.EndOfBuffer;
        }
        const result = self.buffer[self.position .. self.position + n];
        self.position += n;
        return result;
    }

    /// Reset parser position
    pub fn reset(self: *Parser) void {
        self.position = 0;
    }

    /// Check if there are more bytes to read
    pub fn has_more(self: *Parser) bool {
        return self.position < self.buffer.len;
    }
};

test "parser initialization" {
    var buffer: [10]u8 = undefined;
    const parser = Parser.init(std.testing.allocator, &buffer);
    try std.testing.expectEqual(@as(usize, 0), parser.position);
}

test "parser peek and read" {
    var buffer: [3]u8 = .{ 0x05, 0x11, 0x42 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    const peeked = try parser.peek();
    try std.testing.expectEqual(@as(u8, 0x05), peeked);
    try std.testing.expectEqual(@as(usize, 0), parser.position);

    const read_byte = try parser.read();
    try std.testing.expectEqual(@as(u8, 0x05), read_byte);
    try std.testing.expectEqual(@as(usize, 1), parser.position);
}

test "parser read bytes" {
    var buffer: [5]u8 = .{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    const bytes = try parser.read_bytes(3);
    try std.testing.expectEqual(@as(usize, 3), bytes.len);
    try std.testing.expectEqual(@as(usize, 3), parser.position);
}

test "parser end of buffer" {
    var buffer: [2]u8 = .{ 0x01, 0x02 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    _ = try parser.read();
    _ = try parser.read();
    const result = parser.peek();
    try std.testing.expectError(error.EndOfBuffer, result);
}

test "parser has_more" {
    var buffer: [2]u8 = .{ 0x01, 0x02 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    try std.testing.expect(parser.has_more());
    _ = try parser.read();
    try std.testing.expect(parser.has_more());
    _ = try parser.read();
    try std.testing.expect(!parser.has_more());
}

test "parser reset" {
    var buffer: [3]u8 = undefined;
    var parser = Parser.init(std.testing.allocator, &buffer);
    parser.position = 2;
    parser.reset();
    try std.testing.expectEqual(@as(usize, 0), parser.position);
}
