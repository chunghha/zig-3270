const std = @import("std");

/// Generic reusable buffer pool for reducing allocations in hot paths
pub fn BufferPool(comptime T: type) type {
    return struct {
        const Self = @This();

        buffers: std.ArrayList([]T),
        allocator: std.mem.Allocator,
        buffer_size: usize,
        allocations: usize = 0,
        deallocations: usize = 0,
        reuses: usize = 0,

        pub fn init(allocator: std.mem.Allocator, buffer_size: usize) Self {
            return Self{
                .buffers = std.ArrayList([]T).init(allocator),
                .allocator = allocator,
                .buffer_size = buffer_size,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.buffers.items) |buf| {
                self.allocator.free(buf);
            }
            self.buffers.deinit();
        }

        /// Acquire a buffer from the pool or allocate a new one
        pub fn acquire(self: *Self) ![]T {
            if (self.buffers.popOrNull()) |buf| {
                self.reuses += 1;
                return buf;
            }
            self.allocations += 1;
            return try self.allocator.alloc(T, self.buffer_size);
        }

        /// Return a buffer to the pool for reuse
        pub fn release(self: *Self, buf: []T) !void {
            if (buf.len != self.buffer_size) {
                self.allocator.free(buf);
                return;
            }
            self.deallocations += 1;
            try self.buffers.append(buf);
        }

        /// Get current pool size (number of available buffers)
        pub fn poolSize(self: *const Self) usize {
            return self.buffers.items.len;
        }

        /// Print statistics
        pub fn printStats(self: *const Self) void {
            const hit_rate = if (self.allocations + self.reuses > 0)
                @as(f64, @floatFromInt(self.reuses)) / @as(f64, @floatFromInt(self.allocations + self.reuses)) * 100.0
            else
                0.0;

            std.debug.print(
                "Buffer Pool: {} allocations, {} reuses, {d:.1}% hit rate, {} in pool\n",
                .{ self.allocations, self.reuses, hit_rate, self.poolSize() },
            );
        }
    };
}

/// Pool for command data buffers (typical size: 1920 for screen buffer)
pub const CommandBufferPool = BufferPool(u8);

/// Pool for screen buffers
pub const ScreenBufferPool = BufferPool(u8);

/// Pool with variable buffer sizes
pub const VariableBufferPool = struct {
    const Self = @This();

    buffers: std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    allocations: usize = 0,
    deallocations: usize = 0,
    reuses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .buffers = std.ArrayList([]u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffers.items) |buf| {
            self.allocator.free(buf);
        }
        self.buffers.deinit();
    }

    /// Acquire a buffer of at least the requested size
    pub fn acquire(self: *Self, min_size: usize) ![]u8 {
        // Try to find a buffer that fits
        var best_idx: ?usize = null;
        var best_size: usize = std.math.maxInt(usize);

        for (self.buffers.items, 0..) |buf, i| {
            if (buf.len >= min_size and buf.len < best_size) {
                best_idx = i;
                best_size = buf.len;
            }
        }

        if (best_idx) |idx| {
            const buf = self.buffers.orderedRemove(idx);
            self.reuses += 1;
            return buf;
        }

        self.allocations += 1;
        return try self.allocator.alloc(u8, min_size);
    }

    /// Return a buffer to the pool for reuse
    pub fn release(self: *Self, buf: []u8) !void {
        self.deallocations += 1;
        try self.buffers.append(buf);
    }

    /// Get current pool size
    pub fn poolSize(self: *const Self) usize {
        return self.buffers.items.len;
    }

    /// Clear the pool and free all buffers
    pub fn clear(self: *Self) void {
        for (self.buffers.items) |buf| {
            self.allocator.free(buf);
        }
        self.buffers.clearRetainingCapacity();
    }

    /// Print statistics
    pub fn printStats(self: *const Self) void {
        const hit_rate = if (self.allocations + self.reuses > 0)
            @as(f64, @floatFromInt(self.reuses)) / @as(f64, @floatFromInt(self.allocations + self.reuses)) * 100.0
        else
            0.0;

        std.debug.print(
            "Variable Buffer Pool: {} allocations, {} reuses, {d:.1}% hit rate, {} in pool\n",
            .{ self.allocations, self.reuses, hit_rate, self.poolSize() },
        );
    }
};

test "buffer pool: fixed size pool basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = CommandBufferPool.init(allocator, 1024);
    defer pool.deinit();

    // First acquire: allocates
    const buf1 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1), pool.allocations);
    try std.testing.expectEqual(@as(usize, 0), pool.reuses);

    // Release back to pool
    try pool.release(buf1);
    try std.testing.expectEqual(@as(usize, 1), pool.deallocations);

    // Second acquire: reuses
    const buf2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1), pool.allocations);
    try std.testing.expectEqual(@as(usize, 1), pool.reuses);

    try pool.release(buf2);
}

test "buffer pool: variable size pool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = VariableBufferPool.init(allocator);
    defer pool.deinit();

    // Acquire different sizes
    const buf1 = try pool.acquire(512);
    const buf2 = try pool.acquire(1024);
    try std.testing.expectEqual(@as(usize, 2), pool.allocations);

    // Release both
    try pool.release(buf1);
    try pool.release(buf2);

    // Acquire fits the smaller one
    const buf3 = try pool.acquire(256);
    try std.testing.expectEqual(@as(usize, 512), buf3.len);
    try std.testing.expectEqual(@as(usize, 1), pool.reuses);

    try pool.release(buf3);
}

test "buffer pool: oversized buffer not reused" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = CommandBufferPool.init(allocator, 256);
    defer pool.deinit();

    // Acquire standard size
    const buf = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 256), buf.len);

    // Try to release wrong size buffer
    const wrong_buf = try allocator.alloc(u8, 512);
    try pool.release(wrong_buf);

    // Wrong size is freed, not added to pool
    try std.testing.expectEqual(@as(usize, 0), pool.poolSize());
}
