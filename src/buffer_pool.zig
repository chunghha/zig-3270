const std = @import("std");

/// Reusable buffer pool for command data
/// Reduces allocations in hot path (parser, executor)
pub const BufferPool = struct {
    allocator: std.mem.Allocator,
    available: std.ArrayList([]u8),
    in_use: std.ArrayList([]u8),
    buffer_size: usize,
    stats: PoolStats,

    pub const PoolStats = struct {
        allocations: u64 = 0,
        deallocations: u64 = 0,
        pool_hits: u64 = 0,
        pool_misses: u64 = 0,
        peak_in_use: usize = 0,
    };

    /// Initialize buffer pool with specified buffer size
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) BufferPool {
        return .{
            .allocator = allocator,
            .available = std.ArrayList([]u8).init(allocator),
            .in_use = std.ArrayList([]u8).init(allocator),
            .buffer_size = buffer_size,
            .stats = PoolStats{},
        };
    }

    /// Preallocate N buffers for the pool
    pub fn preallocate(self: *BufferPool, count: usize) !void {
        for (0..count) |_| {
            const buffer = try self.allocator.alloc(u8, self.buffer_size);
            try self.available.append(buffer);
        }
    }

    /// Get a buffer from pool (allocates new if pool empty)
    pub fn get(self: *BufferPool) ![]u8 {
        var buffer: []u8 = undefined;

        if (self.available.items.len > 0) {
            // Reuse from pool
            buffer = self.available.pop();
            self.stats.pool_hits += 1;
        } else {
            // Allocate new
            buffer = try self.allocator.alloc(u8, self.buffer_size);
            self.stats.pool_misses += 1;
            self.stats.allocations += 1;
        }

        try self.in_use.append(buffer);

        // Track peak usage
        if (self.in_use.items.len > self.stats.peak_in_use) {
            self.stats.peak_in_use = self.in_use.items.len;
        }

        return buffer;
    }

    /// Return buffer to pool for reuse
    pub fn put(self: *BufferPool, buffer: []u8) !void {
        // Find and remove from in_use list
        var found = false;
        for (0..self.in_use.items.len) |i| {
            if (self.in_use.items[i].ptr == buffer.ptr) {
                _ = self.in_use.orderedRemove(i);
                found = true;
                break;
            }
        }

        if (!found) {
            return error.BufferNotInUse;
        }

        // Add back to available
        try self.available.append(buffer);
        self.stats.deallocations += 1;
    }

    /// Clear a buffer without returning to pool (drop it)
    pub fn drop(self: *BufferPool, buffer: []u8) !void {
        // Find and remove from in_use
        for (0..self.in_use.items.len) |i| {
            if (self.in_use.items[i].ptr == buffer.ptr) {
                const buf = self.in_use.orderedRemove(i);
                self.allocator.free(buf);
                return;
            }
        }
    }

    /// Get current pool statistics
    pub fn get_stats(self: BufferPool) PoolStats {
        return self.stats;
    }

    /// Get pool utilization (0-100%)
    pub fn utilization(self: BufferPool) f32 {
        if (self.stats.peak_in_use == 0) {
            return 0.0;
        }
        return @as(f32, @floatFromInt(self.in_use.items.len)) /
            @as(f32, @floatFromInt(self.stats.peak_in_use)) * 100.0;
    }

    /// Clear all buffers (used during shutdown)
    pub fn clear(self: *BufferPool) void {
        for (self.available.items) |buffer| {
            self.allocator.free(buffer);
        }
        for (self.in_use.items) |buffer| {
            self.allocator.free(buffer);
        }
        self.available.clearRetainingCapacity();
        self.in_use.clearRetainingCapacity();
    }

    /// Deinitialize pool
    pub fn deinit(self: *BufferPool) void {
        self.clear();
        self.available.deinit();
        self.in_use.deinit();
    }
};

/// Pool for common screen buffer size (24x80 = 1920 bytes)
pub const ScreenBufferPool = struct {
    pool: BufferPool,

    pub const SCREEN_SIZE = 24 * 80; // 1920 bytes

    /// Initialize screen buffer pool
    pub fn init(allocator: std.mem.Allocator) ScreenBufferPool {
        return .{
            .pool = BufferPool.init(allocator, SCREEN_SIZE),
        };
    }

    /// Preallocate screen buffers
    pub fn preallocate(self: *ScreenBufferPool, count: usize) !void {
        try self.pool.preallocate(count);
    }

    /// Get a screen buffer
    pub fn get(self: *ScreenBufferPool) ![]u8 {
        return self.pool.get();
    }

    /// Return screen buffer
    pub fn put(self: *ScreenBufferPool, buffer: []u8) !void {
        return self.pool.put(buffer);
    }

    /// Get statistics
    pub fn stats(self: ScreenBufferPool) BufferPool.PoolStats {
        return self.pool.get_stats();
    }

    /// Deinitialize pool
    pub fn deinit(self: *ScreenBufferPool) void {
        self.pool.deinit();
    }
};

/// Variable-size buffer pool with multiple size categories
pub const VariableBufferPool = struct {
    allocator: std.mem.Allocator,
    small_pool: BufferPool, // 256 bytes
    medium_pool: BufferPool, // 1024 bytes
    large_pool: BufferPool, // 4096 bytes

    pub const SMALL_SIZE = 256;
    pub const MEDIUM_SIZE = 1024;
    pub const LARGE_SIZE = 4096;

    /// Initialize variable buffer pool
    pub fn init(allocator: std.mem.Allocator) VariableBufferPool {
        return .{
            .allocator = allocator,
            .small_pool = BufferPool.init(allocator, SMALL_SIZE),
            .medium_pool = BufferPool.init(allocator, MEDIUM_SIZE),
            .large_pool = BufferPool.init(allocator, LARGE_SIZE),
        };
    }

    /// Preallocate buffers in all pools
    pub fn preallocate(self: *VariableBufferPool, small: usize, medium: usize, large: usize) !void {
        try self.small_pool.preallocate(small);
        try self.medium_pool.preallocate(medium);
        try self.large_pool.preallocate(large);
    }

    /// Get appropriately-sized buffer
    pub fn get(self: *VariableBufferPool, size: usize) ![]u8 {
        if (size <= SMALL_SIZE) {
            return self.small_pool.get();
        } else if (size <= MEDIUM_SIZE) {
            return self.medium_pool.get();
        } else if (size <= LARGE_SIZE) {
            return self.large_pool.get();
        } else {
            // Allocate directly for oversized requests
            return self.allocator.alloc(u8, size);
        }
    }

    /// Return buffer to appropriate pool
    pub fn put(self: *VariableBufferPool, buffer: []u8) !void {
        if (buffer.len <= SMALL_SIZE) {
            try self.small_pool.put(buffer);
        } else if (buffer.len <= MEDIUM_SIZE) {
            try self.medium_pool.put(buffer);
        } else if (buffer.len <= LARGE_SIZE) {
            try self.large_pool.put(buffer);
        } else {
            // Free oversized directly
            self.allocator.free(buffer);
        }
    }

    /// Deinitialize all pools
    pub fn deinit(self: *VariableBufferPool) void {
        self.small_pool.deinit();
        self.medium_pool.deinit();
        self.large_pool.deinit();
    }
};

// Tests
test "buffer_pool: init creates empty pool" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.available.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use.items.len);
}

test "buffer_pool: preallocate creates buffers" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    try pool.preallocate(5);

    try std.testing.expectEqual(@as(usize, 5), pool.available.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use.items.len);
}

test "buffer_pool: get allocates from pool" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    try pool.preallocate(3);

    const buffer = try pool.get();

    try std.testing.expectEqual(@as(usize, 2), pool.available.items.len);
    try std.testing.expectEqual(@as(usize, 1), pool.in_use.items.len);
    try std.testing.expectEqual(@as(usize, 256), buffer.len);
}

test "buffer_pool: get allocates new when empty" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    const buffer = try pool.get();

    try std.testing.expectEqual(@as(usize, 1), pool.in_use.items.len);
    try std.testing.expectEqual(@as(usize, 256), buffer.len);
    try std.testing.expectEqual(@as(u64, 1), pool.stats.allocations);
    try std.testing.expectEqual(@as(u64, 1), pool.stats.pool_misses);
}

test "buffer_pool: put returns buffer to pool" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    const buffer = try pool.get();
    try pool.put(buffer);

    try std.testing.expectEqual(@as(usize, 1), pool.available.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use.items.len);
    try std.testing.expectEqual(@as(u64, 1), pool.stats.deallocations);
}

test "buffer_pool: pool_hits increment on reuse" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    try pool.preallocate(1);
    const buffer1 = try pool.get();
    try pool.put(buffer1);
    const buffer2 = try pool.get();

    try std.testing.expectEqual(@as(u64, 1), pool.stats.pool_hits);
    // Both should be same memory
    try std.testing.expectEqual(buffer1.ptr, buffer2.ptr);
}

test "buffer_pool: drop frees buffer" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    const buffer = try pool.get();
    try pool.drop(buffer);

    try std.testing.expectEqual(@as(usize, 0), pool.available.items.len);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use.items.len);
}

test "buffer_pool: utilization calculation" {
    var pool = BufferPool.init(std.testing.allocator, 256);
    defer pool.deinit();

    try pool.preallocate(10);
    _ = try pool.get();
    _ = try pool.get();
    _ = try pool.get();

    const util = pool.utilization();
    try std.testing.expect(util > 0.0);
    try std.testing.expect(util <= 100.0);
}

test "screen_buffer_pool: init creates pool" {
    var pool = ScreenBufferPool.init(std.testing.allocator);
    defer pool.deinit();

    try pool.preallocate(3);
    const buffer = try pool.get();

    try std.testing.expectEqual(@as(usize, 1920), buffer.len);
}

test "variable_buffer_pool: selects correct size" {
    var pool = VariableBufferPool.init(std.testing.allocator);
    defer pool.deinit();

    try pool.preallocate(2, 2, 2);

    const small = try pool.get(128);
    const medium = try pool.get(512);
    const large = try pool.get(2048);

    try std.testing.expectEqual(@as(usize, 256), small.len);
    try std.testing.expectEqual(@as(usize, 1024), medium.len);
    try std.testing.expectEqual(@as(usize, 4096), large.len);

    try pool.put(small);
    try pool.put(medium);
    try pool.put(large);
}

test "variable_buffer_pool: handles oversized requests" {
    var pool = VariableBufferPool.init(std.testing.allocator);
    defer pool.deinit();

    const oversized = try pool.get(16384);

    try std.testing.expectEqual(@as(usize, 16384), oversized.len);

    pool.allocator.free(oversized); // Free directly since not in pool
}
