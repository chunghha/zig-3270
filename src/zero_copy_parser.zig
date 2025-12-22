const std = @import("std");
const protocol = @import("protocol.zig");

/// View-based buffer slicing for zero-copy parsing
/// Avoids allocations by creating views into source buffer
pub const BufferView = struct {
    const Self = @This();

    buffer: []const u8,
    start: usize = 0,
    end: usize,

    /// Initialize a view of entire buffer
    pub fn init(buffer: []const u8) Self {
        return .{
            .buffer = buffer,
            .end = buffer.len,
        };
    }

    /// Create a subview within current view
    pub fn slice(self: Self, offset: usize, length: usize) !Self {
        const absolute_start = self.start + offset;
        const absolute_end = absolute_start + length;

        if (absolute_end > self.end) {
            return error.SliceOutOfBounds;
        }

        return .{
            .buffer = self.buffer,
            .start = absolute_start,
            .end = absolute_end,
        };
    }

    /// Get length of view
    pub fn len(self: Self) usize {
        return self.end - self.start;
    }

    /// Get actual data slice
    pub fn data(self: Self) []const u8 {
        return self.buffer[self.start..self.end];
    }

    /// Peek at offset within view
    pub fn peek(self: Self, offset: usize) !u8 {
        if (self.start + offset >= self.end) {
            return error.OffsetOutOfBounds;
        }
        return self.buffer[self.start + offset];
    }

    /// Slice from current position to end
    pub fn remaining(self: Self, offset: usize) !Self {
        if (self.start + offset > self.end) {
            return error.OffsetOutOfBounds;
        }
        return .{
            .buffer = self.buffer,
            .start = self.start + offset,
            .end = self.end,
        };
    }
};

/// Ring buffer for network I/O with zero-copy views
pub const RingBufferIO = struct {
    const Self = @This();

    buffer: []u8,
    write_pos: usize = 0,
    read_pos: usize = 0,
    capacity: usize,
    allocator: std.mem.Allocator,

    /// Initialize ring buffer for I/O
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        const buffer = try allocator.alloc(u8, capacity);
        return .{
            .buffer = buffer,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    /// Deallocate ring buffer
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    /// Write data to ring buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        if (data.len == 0) return 0;
        if (data.len > self.capacity) return error.BufferTooSmall;

        var written: usize = 0;

        while (written < data.len) {
            const space_until_end = self.capacity - self.write_pos;
            const to_write = @min(space_until_end, data.len - written);

            @memcpy(
                self.buffer[self.write_pos .. self.write_pos + to_write],
                data[written .. written + to_write],
            );

            written += to_write;
            self.write_pos += to_write;

            if (self.write_pos >= self.capacity) {
                self.write_pos = 0;
            }
        }

        return written;
    }

    /// Advance read position
    pub fn advance_read(self: *Self, count: usize) !void {
        const available = self.available();
        if (count > available) {
            return error.AdvanceTooFar;
        }

        self.read_pos += count;
        if (self.read_pos >= self.capacity) {
            self.read_pos -= self.capacity;
        }
    }

    /// Get contiguous view of available data for reading
    /// Returns view of largest contiguous chunk
    pub fn get_read_view(self: Self) !?BufferView {
        if (self.available() == 0) {
            return null;
        }

        if (self.write_pos >= self.read_pos) {
            // Data is contiguous
            return BufferView{
                .buffer = self.buffer,
                .start = self.read_pos,
                .end = self.write_pos,
            };
        } else {
            // Data wraps around, return first contiguous chunk
            return BufferView{
                .buffer = self.buffer,
                .start = self.read_pos,
                .end = self.capacity,
            };
        }
    }

    /// Get available bytes
    pub fn available(self: Self) usize {
        if (self.write_pos >= self.read_pos) {
            return self.write_pos - self.read_pos;
        } else {
            return (self.capacity - self.read_pos) + self.write_pos;
        }
    }

    /// Check if buffer is full
    pub fn is_full(self: Self) bool {
        return self.available() == self.capacity;
    }

    /// Clear buffer
    pub fn clear(self: *Self) void {
        self.read_pos = 0;
        self.write_pos = 0;
    }
};

/// Zero-copy command parser using buffer views
pub const ZeroCopyParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Parse command code from view (no allocation)
    pub fn parse_command_code(view: BufferView) !protocol.CommandCode {
        if (view.len() < 1) {
            return error.InsufficientData;
        }

        const code = try view.peek(0);
        return std.meta.intToEnum(protocol.CommandCode, code) catch |err| {
            return error.InvalidCommandCode;
        };
    }

    /// Parse address (row, col) from view
    pub fn parse_address(view: BufferView) !struct { row: u8, col: u8 } {
        if (view.len() < 2) {
            return error.InsufficientData;
        }

        const byte1 = try view.peek(0);
        const byte2 = try view.peek(1);

        const offset = (@as(u16, byte1) << 8) | @as(u16, byte2);
        const row = @as(u8, @intCast((offset / 80) % 24));
        const col = @as(u8, @intCast(offset % 80));

        return .{ .row = row, .col = col };
    }

    /// Parse field attribute from view
    pub fn parse_field_attribute(view: BufferView) !protocol.FieldAttribute {
        if (view.len() < 1) {
            return error.InsufficientData;
        }

        const byte = try view.peek(0);
        return std.meta.intToEnum(protocol.FieldAttribute, byte) catch |err| {
            return error.InvalidFieldAttribute;
        };
    }

    /// Parse text data from view
    /// Returns view into original buffer (zero-copy)
    pub fn parse_text(view: BufferView, length: usize) !BufferView {
        return try view.slice(0, length);
    }

    /// Parse extended command from view
    pub fn parse_extended_command(view: BufferView) !struct { command: u8, length: usize } {
        if (view.len() < 2) {
            return error.InsufficientData;
        }

        const command = try view.peek(0);
        const length = try view.peek(1);

        return .{ .command = command, .length = length };
    }
};

/// Streaming parser for large frames
pub const StreamingZeroCopyParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: RingBufferIO,
    parsed_elements: std.ArrayList(ParsedElement),

    pub const ParsedElement = struct {
        element_type: ElementType,
        view: BufferView,

        pub const ElementType = enum {
            command_code,
            address,
            field_attribute,
            text_data,
            extended_command,
        };
    };

    /// Initialize streaming parser
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !Self {
        return .{
            .allocator = allocator,
            .buffer = try RingBufferIO.init(allocator, buffer_size),
            .parsed_elements = std.ArrayList(ParsedElement).init(allocator),
        };
    }

    /// Deallocate parser
    pub fn deinit(self: *Self) void {
        self.parsed_elements.deinit();
        self.buffer.deinit();
    }

    /// Feed data into parser
    pub fn feed(self: *Self, data: []const u8) !usize {
        return try self.buffer.write(data);
    }

    /// Parse next available element from buffer
    pub fn parse_next(self: *Self) !?ParsedElement {
        const view = try self.buffer.get_read_view() orelse return null;

        if (view.len() == 0) return null;

        // Try to parse based on first byte
        const first_byte = try view.peek(0);

        // Simple heuristic: check for known command codes
        const cmd_result = std.meta.intToEnum(protocol.CommandCode, first_byte);
        if (cmd_result) |_| {
            try self.buffer.advance_read(1);
            return ParsedElement{
                .element_type = .command_code,
                .view = view,
            };
        } else |_| {
            // Not a command code, might be data
            if (view.len() >= 2) {
                try self.buffer.advance_read(2);
                return ParsedElement{
                    .element_type = .address,
                    .view = view,
                };
            }
        }

        return null;
    }

    /// Parse all available data
    pub fn parse_all(self: *Self) !void {
        while (try self.parse_next()) |elem| {
            try self.parsed_elements.append(elem);
        }
    }

    /// Get parsed elements (view-based, no allocation)
    pub fn get_elements(self: *const Self) []const ParsedElement {
        return self.parsed_elements.items;
    }

    /// Clear parsed elements
    pub fn clear_elements(self: *Self) void {
        self.parsed_elements.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "buffer view: creation and slicing" {
    const data = "Hello, World!";
    var view = BufferView.init(data);

    try std.testing.expectEqual(@as(usize, 13), view.len());
    try std.testing.expectEqualSlices(u8, data, view.data());
}

test "buffer view: slice operations" {
    const data = "0123456789";
    const view = BufferView.init(data);

    const sub = try view.slice(2, 4);
    try std.testing.expectEqual(@as(usize, 4), sub.len());
    try std.testing.expectEqualSlices(u8, "2345", sub.data());
}

test "buffer view: peek at offset" {
    const data = "ABCDEF";
    const view = BufferView.init(data);

    const byte0 = try view.peek(0);
    try std.testing.expectEqual(@as(u8, 'A'), byte0);

    const byte5 = try view.peek(5);
    try std.testing.expectEqual(@as(u8, 'F'), byte5);
}

test "ring buffer io: write and read view" {
    var rb = try RingBufferIO.init(std.testing.allocator, 256);
    defer rb.deinit();

    const data = "TestData";
    _ = try rb.write(data);

    const view = try rb.get_read_view();
    try std.testing.expect(view != null);
    try std.testing.expectEqualSlices(u8, data, view.?.data());
}

test "zero copy parser: command code parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const parser = ZeroCopyParser.init(gpa.allocator());

    // Create a buffer with a valid command code
    const data = [_]u8{ 0xF1, 0x00, 0x00 }; // WriteCommand
    var view = BufferView.init(&data);

    const cmd = try parser.parse_command_code(view);
    try std.testing.expectEqual(protocol.CommandCode.write, cmd);
}

test "zero copy parser: address parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const parser = ZeroCopyParser.init(gpa.allocator());

    // Address for position (0, 0) -> offset 0x0000
    const data = [_]u8{ 0x00, 0x00 };
    var view = BufferView.init(&data);

    const addr = try parser.parse_address(view);
    try std.testing.expectEqual(@as(u8, 0), addr.row);
    try std.testing.expectEqual(@as(u8, 0), addr.col);
}

test "streaming zero copy parser: feed and parse" {
    var parser = try StreamingZeroCopyParser.init(std.testing.allocator, 512);
    defer parser.deinit();

    const data = [_]u8{ 0xF1, 0x42, 0x42 };
    _ = try parser.feed(&data);

    const elem = try parser.parse_next();
    try std.testing.expect(elem != null);
}

test "zero copy parser: text extraction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const parser = ZeroCopyParser.init(gpa.allocator());

    const data = "Hello, World!";
    var view = BufferView.init(data);

    const text_view = try parser.parse_text(view, 5);
    try std.testing.expectEqualSlices(u8, "Hello", text_view.data());
}
