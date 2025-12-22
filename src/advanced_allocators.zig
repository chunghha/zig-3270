const std = @import("std");

/// Ring buffer allocator for circular buffer patterns
/// Useful for streaming data processing with bounded memory
pub const RingBufferAllocator = struct {
    const Self = @This();

    buffer: []u8,
    allocator: std.mem.Allocator,
    write_pos: usize = 0,
    read_pos: usize = 0,
    capacity: usize,
    wraps: u32 = 0,

    /// Initialize ring buffer allocator with specified capacity
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        const buffer = try allocator.alloc(u8, capacity);
        return .{
            .buffer = buffer,
            .allocator = allocator,
            .capacity = capacity,
        };
    }

    /// Deallocate the ring buffer
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    /// Write data to ring buffer, wrapping around if needed
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
                self.wraps += 1;
            }
        }

        return written;
    }

    /// Read data from ring buffer
    pub fn read(self: *Self, out: []u8) !usize {
        if (out.len == 0) return 0;

        const available = self.available();
        const to_read = @min(available, out.len);

        if (to_read == 0) return error.NoData;

        var read_bytes: usize = 0;

        while (read_bytes < to_read) {
            const space_until_end = self.capacity - self.read_pos;
            const read_now = @min(space_until_end, to_read - read_bytes);

            @memcpy(
                out[read_bytes .. read_bytes + read_now],
                self.buffer[self.read_pos .. self.read_pos + read_now],
            );

            read_bytes += read_now;
            self.read_pos += read_now;

            if (self.read_pos >= self.capacity) {
                self.read_pos = 0;
            }
        }

        return read_bytes;
    }

    /// Peek at available data without consuming
    pub fn peek(self: *Self, out: []u8) !usize {
        if (out.len == 0) return 0;

        const available = self.available();
        const to_peek = @min(available, out.len);

        if (to_peek == 0) return error.NoData;

        var peeked: usize = 0;
        var read_pos = self.read_pos;

        while (peeked < to_peek) {
            const space_until_end = self.capacity - read_pos;
            const peek_now = @min(space_until_end, to_peek - peeked);

            @memcpy(
                out[peeked .. peeked + peek_now],
                self.buffer[read_pos .. read_pos + peek_now],
            );

            peeked += peek_now;
            read_pos += peek_now;

            if (read_pos >= self.capacity) {
                read_pos = 0;
            }
        }

        return peeked;
    }

    /// Get available bytes in buffer
    pub fn available(self: *const Self) usize {
        if (self.write_pos >= self.read_pos) {
            return self.write_pos - self.read_pos;
        } else {
            return (self.capacity - self.read_pos) + self.write_pos;
        }
    }

    /// Get free space in buffer
    pub fn free_space(self: *const Self) usize {
        return self.capacity - self.available();
    }

    /// Clear the buffer
    pub fn clear(self: *Self) void {
        self.write_pos = 0;
        self.read_pos = 0;
    }

    /// Check if buffer is full
    pub fn is_full(self: *const Self) bool {
        return self.available() == self.capacity;
    }

    /// Check if buffer is empty
    pub fn is_empty(self: *const Self) bool {
        return self.available() == 0;
    }
};

/// Fixed-size pool allocator - allocates fixed-size blocks efficiently
pub const FixedPoolAllocator = struct {
    const Self = @This();
    const BlockHeader = packed struct {
        is_free: bool,
        size: u31,
    };

    allocator: std.mem.Allocator,
    buffer: []u8,
    block_size: usize,
    num_blocks: usize,
    free_blocks: std.ArrayList(usize),
    stats: Stats = .{},

    pub const Stats = struct {
        allocations: u32 = 0,
        deallocations: u32 = 0,
        reuses: u32 = 0,
    };

    /// Initialize fixed pool allocator
    pub fn init(allocator: std.mem.Allocator, block_size: usize, num_blocks: usize) !Self {
        const buffer = try allocator.alloc(u8, block_size * num_blocks);

        var free_blocks = std.ArrayList(usize).init(allocator);
        for (0..num_blocks) |i| {
            try free_blocks.append(i);
        }

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .block_size = block_size,
            .num_blocks = num_blocks,
            .free_blocks = free_blocks,
        };
    }

    /// Deallocate the pool
    pub fn deinit(self: *Self) void {
        self.free_blocks.deinit();
        self.allocator.free(self.buffer);
    }

    /// Allocate a fixed-size block
    pub fn allocate(self: *Self) ![]u8 {
        if (self.free_blocks.items.len == 0) {
            return error.PoolExhausted;
        }

        const block_idx = self.free_blocks.pop();
        const start = block_idx * self.block_size;
        const end = start + self.block_size;

        self.stats.allocations += 1;
        self.stats.reuses += 1;

        return self.buffer[start..end];
    }

    /// Deallocate a block back to the pool
    pub fn deallocate(self: *Self, block: []u8) !void {
        if (block.len != self.block_size) {
            return error.InvalidBlockSize;
        }

        const block_ptr = block.ptr;
        const buffer_ptr = self.buffer.ptr;

        if (@intFromPtr(block_ptr) < @intFromPtr(buffer_ptr)) {
            return error.BlockNotFromPool;
        }

        const offset = @intFromPtr(block_ptr) - @intFromPtr(buffer_ptr);

        if (offset % self.block_size != 0) {
            return error.MisalignedBlock;
        }

        const block_idx = offset / self.block_size;

        if (block_idx >= self.num_blocks) {
            return error.BlockOutOfRange;
        }

        try self.free_blocks.append(block_idx);
        self.stats.deallocations += 1;
    }

    /// Get number of free blocks
    pub fn free_count(self: *const Self) usize {
        return self.free_blocks.items.len;
    }

    /// Get statistics
    pub fn get_stats(self: *const Self) Stats {
        return self.stats;
    }
};

/// Thread-local scratch allocator for temporary allocations in hot paths
pub const ScratchAllocator = struct {
    const Self = @This();
    const ChunkSize = 4096; // 4KB chunks

    allocator: std.mem.Allocator,
    chunks: std.ArrayList([]u8),
    current_chunk: ?[]u8 = null,
    current_offset: usize = 0,
    stats: Stats = .{},

    pub const Stats = struct {
        chunk_allocations: u32 = 0,
        resets: u32 = 0,
        peak_bytes_used: usize = 0,
        current_bytes_used: usize = 0,
    };

    /// Initialize scratch allocator
    pub fn init(allocator: std.mem.Allocator) !Self {
        var chunks = std.ArrayList([]u8).init(allocator);
        const initial_chunk = try allocator.alloc(u8, ChunkSize);
        try chunks.append(initial_chunk);

        return .{
            .allocator = allocator,
            .chunks = chunks,
            .current_chunk = initial_chunk,
            .current_offset = 0,
        };
    }

    /// Deallocate scratch allocator
    pub fn deinit(self: *Self) void {
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk);
        }
        self.chunks.deinit();
    }

    /// Allocate from scratch space
    pub fn alloc(self: *Self, size: usize) ![]u8 {
        if (size == 0) return &.{};

        const current_chunk = self.current_chunk orelse return error.NoChunk;

        // Check if allocation fits in current chunk
        if (self.current_offset + size <= current_chunk.len) {
            const result = current_chunk[self.current_offset .. self.current_offset + size];
            self.current_offset += size;
            self.stats.current_bytes_used += size;
            if (self.stats.current_bytes_used > self.stats.peak_bytes_used) {
                self.stats.peak_bytes_used = self.stats.current_bytes_used;
            }
            return result;
        }

        // Need new chunk
        if (size > ChunkSize) {
            // Allocation larger than chunk size
            const large_chunk = try self.allocator.alloc(u8, size);
            try self.chunks.append(large_chunk);
            self.stats.chunk_allocations += 1;
            self.stats.current_bytes_used += size;
            if (self.stats.current_bytes_used > self.stats.peak_bytes_used) {
                self.stats.peak_bytes_used = self.stats.current_bytes_used;
            }
            return large_chunk;
        }

        // Allocate new standard chunk
        const new_chunk = try self.allocator.alloc(u8, ChunkSize);
        try self.chunks.append(new_chunk);
        self.current_chunk = new_chunk;
        self.current_offset = size;
        self.stats.chunk_allocations += 1;
        self.stats.current_bytes_used = size;
        if (self.stats.current_bytes_used > self.stats.peak_bytes_used) {
            self.stats.peak_bytes_used = self.stats.current_bytes_used;
        }
        return new_chunk[0..size];
    }

    /// Reset scratch allocator (clears for reuse)
    pub fn reset(self: *Self) void {
        self.current_offset = 0;
        self.stats.resets += 1;
        self.stats.current_bytes_used = 0;
        if (self.chunks.items.len > 0) {
            self.current_chunk = self.chunks.items[0];
        }
    }

    /// Get statistics
    pub fn get_stats(self: *const Self) Stats {
        return self.stats;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ring buffer allocator: basic write and read" {
    var rb = try RingBufferAllocator.init(std.testing.allocator, 256);
    defer rb.deinit();

    const data = "Hello, World!";
    const written = try rb.write(data);
    try std.testing.expectEqual(@as(usize, 13), written);
    try std.testing.expectEqual(@as(usize, 13), rb.available());

    var out: [20]u8 = undefined;
    const read_bytes = try rb.read(&out);
    try std.testing.expectEqual(@as(usize, 13), read_bytes);
    try std.testing.expectEqualSlices(u8, data, out[0..read_bytes]);
}

test "ring buffer allocator: wraparound handling" {
    var rb = try RingBufferAllocator.init(std.testing.allocator, 16);
    defer rb.deinit();

    // Fill buffer
    const data1 = "12345678";
    _ = try rb.write(data1);

    var out1: [8]u8 = undefined;
    const read1 = try rb.read(&out1);
    try std.testing.expectEqual(@as(usize, 8), read1);

    // Write more data (should wrap)
    const data2 = "abcdefghijkl";
    const written2 = try rb.write(data2);
    try std.testing.expectEqual(@as(usize, 12), written2);

    var out2: [16]u8 = undefined;
    const read2 = try rb.read(&out2);
    try std.testing.expectEqual(@as(usize, 12), read2);
}

test "ring buffer allocator: peek without consuming" {
    var rb = try RingBufferAllocator.init(std.testing.allocator, 256);
    defer rb.deinit();

    const data = "TestData";
    _ = try rb.write(data);

    var peek_out: [20]u8 = undefined;
    const peeked = try rb.peek(&peek_out);
    try std.testing.expectEqual(@as(usize, 8), peeked);

    // Should still have data available
    try std.testing.expectEqual(@as(usize, 8), rb.available());

    var read_out: [20]u8 = undefined;
    const read_bytes = try rb.read(&read_out);
    try std.testing.expectEqual(@as(usize, 8), read_bytes);
}

test "fixed pool allocator: basic allocation and deallocation" {
    var pool = try FixedPoolAllocator.init(std.testing.allocator, 128, 4);
    defer pool.deinit();

    const block1 = try pool.allocate();
    try std.testing.expectEqual(@as(usize, 128), block1.len);
    try std.testing.expectEqual(@as(usize, 3), pool.free_count());

    try pool.deallocate(block1);
    try std.testing.expectEqual(@as(usize, 4), pool.free_count());
}

test "fixed pool allocator: exhaustion detection" {
    var pool = try FixedPoolAllocator.init(std.testing.allocator, 64, 2);
    defer pool.deinit();

    const b1 = try pool.allocate();
    const b2 = try pool.allocate();
    try std.testing.expectEqual(@as(usize, 0), pool.free_count());

    // Third allocation should fail
    const result = pool.allocate();
    try std.testing.expectError(error.PoolExhausted, result);

    try pool.deallocate(b1);
    _ = try pool.allocate();
}

test "fixed pool allocator: block reuse tracking" {
    var pool = try FixedPoolAllocator.init(std.testing.allocator, 32, 2);
    defer pool.deinit();

    var stats = pool.get_stats();
    try std.testing.expectEqual(@as(u32, 0), stats.deallocations);

    const b1 = try pool.allocate();
    stats = pool.get_stats();
    try std.testing.expectEqual(@as(u32, 1), stats.allocations);

    try pool.deallocate(b1);
    stats = pool.get_stats();
    try std.testing.expectEqual(@as(u32, 1), stats.deallocations);
}

test "scratch allocator: basic allocation" {
    var scratch = try ScratchAllocator.init(std.testing.allocator);
    defer scratch.deinit();

    const data1 = try scratch.alloc(32);
    try std.testing.expectEqual(@as(usize, 32), data1.len);

    const data2 = try scratch.alloc(64);
    try std.testing.expectEqual(@as(usize, 64), data2.len);

    var stats = scratch.get_stats();
    try std.testing.expectEqual(@as(u32, 1), stats.chunk_allocations);
}

test "scratch allocator: reset functionality" {
    var scratch = try ScratchAllocator.init(std.testing.allocator);
    defer scratch.deinit();

    _ = try scratch.alloc(128);
    var stats = scratch.get_stats();
    try std.testing.expect(stats.current_bytes_used > 0);

    scratch.reset();
    stats = scratch.get_stats();
    try std.testing.expectEqual(@as(usize, 0), stats.current_bytes_used);
    try std.testing.expectEqual(@as(u32, 1), stats.resets);
}

test "scratch allocator: large allocation spanning chunks" {
    var scratch = try ScratchAllocator.init(std.testing.allocator);
    defer scratch.deinit();

    const large = try scratch.alloc(8192); // Larger than ChunkSize
    try std.testing.expectEqual(@as(usize, 8192), large.len);

    var stats = scratch.get_stats();
    try std.testing.expect(stats.chunk_allocations > 1);
}
