const std = @import("std");

/// Handle to field data stored in external storage
pub const FieldHandle = struct {
    storage_id: u32,
    offset: usize,
    length: usize,
};

/// Externalizes field data to reduce allocations
/// Instead of N allocations (one per field), uses a single buffer with range tracking
pub const FieldDataStorage = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []u8,
    field_ranges: std.ArrayList([2]usize), // [offset, length] for each field
    total_capacity: usize,
    used: usize = 0,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        const data = try allocator.alloc(u8, capacity);
        @memset(data, ' ');

        return Self{
            .allocator = allocator,
            .data = data,
            .field_ranges = std.ArrayList([2]usize).init(allocator),
            .total_capacity = capacity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
        self.field_ranges.deinit();
    }

    /// Allocate space for a field and return a handle
    pub fn allocate(self: *Self, size: usize) !FieldHandle {
        if (self.used + size > self.total_capacity) {
            return error.OutOfSpace;
        }

        const handle = FieldHandle{
            .storage_id = 0,
            .offset = self.used,
            .length = size,
        };

        try self.field_ranges.append([2]usize{ self.used, size });
        self.used += size;
        return handle;
    }

    /// Get data slice for a field handle
    pub fn getData(self: *Self, handle: FieldHandle) []u8 {
        return self.data[handle.offset .. handle.offset + handle.length];
    }

    /// Get const data slice for a field handle
    pub fn getDataConst(self: *const Self, handle: FieldHandle) []const u8 {
        return self.data[handle.offset .. handle.offset + handle.length];
    }

    /// Set character in field data
    pub fn setChar(self: *Self, handle: FieldHandle, offset: usize, char: u8) !void {
        if (offset >= handle.length) {
            return error.OutOfBounds;
        }
        self.data[handle.offset + offset] = char;
    }

    /// Get character from field data
    pub fn getChar(self: *const Self, handle: FieldHandle, offset: usize) !u8 {
        if (offset >= handle.length) {
            return error.OutOfBounds;
        }
        return self.data[handle.offset + offset];
    }

    /// Copy data to field
    pub fn copyData(self: *Self, handle: FieldHandle, source: []const u8) !void {
        if (source.len > handle.length) {
            return error.TooMuch;
        }
        @memcpy(self.data[handle.offset .. handle.offset + source.len], source);
    }

    /// Get memory usage statistics
    pub fn getStats(self: *const Self) struct { used: usize, capacity: usize, fields: usize } {
        return .{
            .used = self.used,
            .capacity = self.total_capacity,
            .fields = self.field_ranges.items.len,
        };
    }

    /// Print storage statistics
    pub fn printStats(self: *const Self) void {
        const usage_pct = @as(f64, @floatFromInt(self.used)) / @as(f64, @floatFromInt(self.total_capacity)) * 100.0;
        std.debug.print(
            "Field Storage: {} fields, {} bytes used / {} total ({d:.1}%)\n",
            .{ self.field_ranges.items.len, self.used, self.total_capacity, usage_pct },
        );
    }
};

test "field storage: basic allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var storage = try FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    const handle1 = try storage.allocate(40);
    const handle2 = try storage.allocate(80);

    const stats = storage.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.fields);
    try std.testing.expectEqual(@as(usize, 120), stats.used);
}

test "field storage: character operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var storage = try FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    const handle = try storage.allocate(40);

    // Set character
    try storage.setChar(handle, 5, 'A');
    const ch = try storage.getChar(handle, 5);
    try std.testing.expectEqual(@as(u8, 'A'), ch);
}

test "field storage: copy data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var storage = try FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    const handle = try storage.allocate(40);
    const test_data = "Hello";

    try storage.copyData(handle, test_data);
    const data = storage.getData(handle);
    try std.testing.expectEqualSlices(u8, "Hello", data[0..5]);
}

test "field storage: out of bounds error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var storage = try FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    const handle = try storage.allocate(10);
    const result = storage.setChar(handle, 20, 'A');

    try std.testing.expectError(error.OutOfBounds, result);
}

test "field storage: single allocation vs multiple" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Single storage: 1 allocation
    var storage = try FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    for (0..20) |_| {
        _ = try storage.allocate(96);
    }

    const stats = storage.getStats();
    try std.testing.expectEqual(@as(usize, 20), stats.fields);
    // All in one buffer
    try std.testing.expectEqual(@as(usize, 1920), stats.used);
}
