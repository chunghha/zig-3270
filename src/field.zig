const std = @import("std");
const protocol = @import("protocol.zig");

/// 3270 Field definition
pub const Field = struct {
    start_address: u16,
    length: u16,
    attribute: protocol.FieldAttribute,
    content: []u8,

    pub fn deinit(self: *Field, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }

    /// Check if an address is within this field
    pub fn contains(self: *Field, address: u16) bool {
        return address >= self.start_address and address < self.start_address + self.length;
    }

    /// Get character at offset within field
    pub fn get_char(self: *Field, offset: u16) !u8 {
        if (offset >= self.length) {
            return error.OutOfBounds;
        }
        return self.content[offset];
    }

    /// Set character at offset within field
    pub fn set_char(self: *Field, offset: u16, char: u8) !void {
        if (offset >= self.length) {
            return error.OutOfBounds;
        }
        self.content[offset] = char;
    }
};

/// Field manager for 3270 screen
pub const FieldManager = struct {
    allocator: std.mem.Allocator,
    fields: std.ArrayList(Field),

    pub fn init(allocator: std.mem.Allocator) FieldManager {
        return FieldManager{
            .allocator = allocator,
            .fields = std.ArrayList(Field).initCapacity(allocator, 0) catch std.ArrayList(Field){
                .items = &.{},
                .capacity = 0,
            },
        };
    }

    pub fn deinit(self: *FieldManager) void {
        for (self.fields.items) |*field| {
            field.deinit(self.allocator);
        }
        self.fields.deinit(self.allocator);
    }

    /// Add a new field
    pub fn add_field(self: *FieldManager, start_address: u16, length: u16, attr: protocol.FieldAttribute) !*Field {
        const content = try self.allocator.alloc(u8, length);
        @memset(content, ' ');

        const field = Field{
            .start_address = start_address,
            .length = length,
            .attribute = attr,
            .content = content,
        };

        try self.fields.append(self.allocator, field);
        return &self.fields.items[self.fields.items.len - 1];
    }

    /// Find field at address
    pub fn find_field(self: *FieldManager, address: u16) ?*Field {
        for (self.fields.items) |*field| {
            if (field.contains(address)) {
                return field;
            }
        }
        return null;
    }

    /// Get field by index
    pub fn get_field(self: *FieldManager, index: usize) ?*Field {
        if (index >= self.fields.items.len) {
            return null;
        }
        return &self.fields.items[index];
    }

    /// Get next unprotected field from address
    pub fn next_unprotected_field(self: *FieldManager, address: u16) ?*Field {
        var found_start = false;

        for (self.fields.items) |*field| {
            if (field.start_address >= address) {
                found_start = true;
            }
            if (found_start and !field.attribute.protected) {
                return field;
            }
        }

        // Wrap around to beginning
        for (self.fields.items) |*field| {
            if (!field.attribute.protected) {
                return field;
            }
        }

        return null;
    }

    /// Clear all fields
    pub fn clear(self: *FieldManager) void {
        for (self.fields.items) |*field| {
            @memset(field.content, ' ');
        }
    }

    /// Count fields
    pub fn count(self: *FieldManager) usize {
        return self.fields.items.len;
    }
};

test "field contains address" {
    var field = Field{
        .start_address = 10,
        .length = 20,
        .attribute = .{},
        .content = &.{},
    };

    try std.testing.expect(field.contains(10));
    try std.testing.expect(field.contains(15));
    try std.testing.expect(field.contains(29));
    try std.testing.expect(!field.contains(9));
    try std.testing.expect(!field.contains(30));
}

test "field get set char" {
    var allocator = std.testing.allocator;
    const content = try allocator.alloc(u8, 5);
    defer allocator.free(content);
    @memset(content, ' ');

    var field = Field{
        .start_address = 0,
        .length = 5,
        .attribute = .{},
        .content = content,
    };

    try field.set_char(0, 'A');
    try std.testing.expectEqual(@as(u8, 'A'), try field.get_char(0));
}

test "field manager initialization" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(usize, 0), fm.count());
}

test "field manager add field" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    const field = try fm.add_field(0, 10, .{});
    try std.testing.expectEqual(@as(u16, 0), field.start_address);
    try std.testing.expectEqual(@as(u16, 10), field.length);
    try std.testing.expectEqual(@as(usize, 1), fm.count());
}

test "field manager find field" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{});
    _ = try fm.add_field(10, 15, .{});

    const field = fm.find_field(12);
    try std.testing.expect(field != null);
    if (field) |f| {
        try std.testing.expectEqual(@as(u16, 10), f.start_address);
    }
}

test "field manager protected vs unprotected" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = true });
    _ = try fm.add_field(10, 10, .{ .protected = false });

    const unprotected = fm.next_unprotected_field(0);
    try std.testing.expect(unprotected != null);
    if (unprotected) |f| {
        try std.testing.expectEqual(@as(u16, 10), f.start_address);
    }
}

test "field manager next unprotected wraps" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    _ = try fm.add_field(0, 10, .{ .protected = false });
    _ = try fm.add_field(10, 10, .{ .protected = true });

    const unprotected = fm.next_unprotected_field(15);
    try std.testing.expect(unprotected != null);
    if (unprotected) |f| {
        try std.testing.expectEqual(@as(u16, 0), f.start_address);
    }
}

test "field manager clear fields" {
    var fm = FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    const field = try fm.add_field(0, 5, .{});
    try field.set_char(0, 'X');
    fm.clear();

    try std.testing.expectEqual(@as(u8, ' '), try field.get_char(0));
}
