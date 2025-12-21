const std = @import("std");
const protocol = @import("protocol.zig");
const attributes_mod = @import("attributes.zig");

/// External field data storage to reduce per-field allocations
/// Moves field data out of Field struct for better memory locality
pub const FieldDataStorage = struct {
    allocator: std.mem.Allocator,
    data_buffer: []u8,
    field_ranges: std.ArrayList(FieldRange),
    total_size: usize,

    pub const FieldRange = struct {
        offset: usize,
        length: usize,
    };

    /// Initialize field storage with total capacity
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !FieldDataStorage {
        return .{
            .allocator = allocator,
            .data_buffer = try allocator.alloc(u8, capacity),
            .field_ranges = std.ArrayList(FieldRange).init(allocator),
            .total_size = 0,
        };
    }

    /// Add field data and return handle
    pub fn add_field(self: *FieldDataStorage, data: []const u8) !usize {
        const handle = self.field_ranges.items.len;

        // Check capacity
        if (self.total_size + data.len > self.data_buffer.len) {
            return error.StorageFull;
        }

        // Copy data
        @memcpy(self.data_buffer[self.total_size .. self.total_size + data.len], data);

        // Record range
        try self.field_ranges.append(.{
            .offset = self.total_size,
            .length = data.len,
        });

        self.total_size += data.len;
        return handle;
    }

    /// Get field data by handle
    pub fn get_field(self: FieldDataStorage, handle: usize) ?[]u8 {
        if (handle >= self.field_ranges.items.len) {
            return null;
        }

        const range = self.field_ranges.items[handle];
        return self.data_buffer[range.offset .. range.offset + range.length];
    }

    /// Update field data by handle
    pub fn update_field(self: *FieldDataStorage, handle: usize, data: []const u8) !void {
        if (handle >= self.field_ranges.items.len) {
            return error.InvalidHandle;
        }

        const range = self.field_ranges.items[handle];
        if (data.len != range.length) {
            return error.SizeeMismatch;
        }

        @memcpy(self.data_buffer[range.offset .. range.offset + range.length], data);
    }

    /// Get field size by handle
    pub fn get_field_size(self: FieldDataStorage, handle: usize) ?usize {
        if (handle >= self.field_ranges.items.len) {
            return null;
        }
        return self.field_ranges.items[handle].length;
    }

    /// Clear all fields
    pub fn clear(self: *FieldDataStorage) void {
        self.field_ranges.clearRetainingCapacity();
        self.total_size = 0;
    }

    /// Get memory usage statistics
    pub fn get_stats(self: FieldDataStorage) StorageStats {
        return .{
            .capacity = self.data_buffer.len,
            .used = self.total_size,
            .field_count = self.field_ranges.items.len,
            .utilization_percent = @as(f32, @floatFromInt(self.total_size * 100)) /
                @as(f32, @floatFromInt(self.data_buffer.len)),
        };
    }

    /// Deinitialize storage
    pub fn deinit(self: *FieldDataStorage) void {
        self.allocator.free(self.data_buffer);
        self.field_ranges.deinit();
    }
};

pub const StorageStats = struct {
    capacity: usize,
    used: usize,
    field_count: usize,
    utilization_percent: f32,
};

/// Field reference using externalized data storage
pub const FieldHandle = struct {
    storage: *FieldDataStorage,
    handle: usize,
    row: u16,
    col: u16,
    attr: attributes_mod.FieldAttribute,

    /// Get field data
    pub fn get_data(self: FieldHandle) ?[]u8 {
        return self.storage.get_field(self.handle);
    }

    /// Get field size
    pub fn get_size(self: FieldHandle) ?usize {
        return self.storage.get_field_size(self.handle);
    }

    /// Update field data
    pub fn set_data(self: FieldHandle, data: []const u8) !void {
        try self.storage.update_field(self.handle, data);
    }
};

// Tests
test "field_data_storage: init creates buffer" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    try std.testing.expectEqual(@as(usize, 0), storage.total_size);
    try std.testing.expectEqual(@as(usize, 0), storage.field_ranges.items.len);
}

test "field_data_storage: add_field stores data" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const handle = try storage.add_field("Test Field");

    try std.testing.expectEqual(@as(usize, 0), handle);
    try std.testing.expectEqual(@as(usize, 10), storage.total_size);
    try std.testing.expectEqual(@as(usize, 1), storage.field_ranges.items.len);
}

test "field_data_storage: get_field retrieves data" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const handle = try storage.add_field("Hello");
    const data = storage.get_field(handle);

    try std.testing.expect(data != null);
    try std.testing.expectEqualSlices(u8, "Hello", data.?);
}

test "field_data_storage: multiple fields" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const h1 = try storage.add_field("Field 1");
    const h2 = try storage.add_field("Field 2");
    const h3 = try storage.add_field("Field 3");

    try std.testing.expectEqual(@as(usize, 0), h1);
    try std.testing.expectEqual(@as(usize, 1), h2);
    try std.testing.expectEqual(@as(usize, 2), h3);

    try std.testing.expectEqualSlices(u8, "Field 1", storage.get_field(h1).?);
    try std.testing.expectEqualSlices(u8, "Field 2", storage.get_field(h2).?);
    try std.testing.expectEqualSlices(u8, "Field 3", storage.get_field(h3).?);
}

test "field_data_storage: update_field modifies data" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const handle = try storage.add_field("Hello");
    try storage.update_field(handle, "World");

    try std.testing.expectEqualSlices(u8, "World", storage.get_field(handle).?);
}

test "field_data_storage: get_field_size returns correct size" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const h1 = try storage.add_field("Test");
    const h2 = try storage.add_field("Longer Field");

    try std.testing.expectEqual(@as(usize, 4), storage.get_field_size(h1).?);
    try std.testing.expectEqual(@as(usize, 12), storage.get_field_size(h2).?);
}

test "field_data_storage: clear resets storage" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    _ = try storage.add_field("Data");
    storage.clear();

    try std.testing.expectEqual(@as(usize, 0), storage.total_size);
    try std.testing.expectEqual(@as(usize, 0), storage.field_ranges.items.len);
}

test "field_data_storage: get_stats reports utilization" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    _ = try storage.add_field("Test");
    const stats = storage.get_stats();

    try std.testing.expectEqual(@as(usize, 1024), stats.capacity);
    try std.testing.expectEqual(@as(usize, 4), stats.used);
    try std.testing.expectEqual(@as(usize, 1), stats.field_count);
}

test "field_data_storage: error on full storage" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 10);
    defer storage.deinit();

    _ = try storage.add_field("12345");
    const result = storage.add_field("67890abcdef");

    try std.testing.expectError(error.StorageFull, result);
}

test "field_handle: access through handle" {
    var storage = try FieldDataStorage.init(std.testing.allocator, 1024);
    defer storage.deinit();

    const handle = try storage.add_field("Test");
    var attr: attributes_mod.FieldAttribute = undefined;
    attr.intensified = false;
    attr.protected = false;
    attr.hidden = false;
    attr.numeric = false;

    var fh = FieldHandle{
        .storage = &storage,
        .handle = handle,
        .row = 5,
        .col = 10,
        .attr = attr,
    };

    try std.testing.expectEqualSlices(u8, "Test", fh.get_data().?);
    try std.testing.expectEqual(@as(usize, 4), fh.get_size().?);
}
