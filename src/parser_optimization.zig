const std = @import("std");

/// Parser optimization metrics and strategies
/// Single-pass parsing with minimal allocations
pub const ParserMetrics = struct {
    bytes_processed: u64 = 0,
    commands_parsed: u64 = 0,
    allocations: u64 = 0,
    peak_memory: usize = 0,
    start_time: i64 = 0,

    pub fn elapsed_ms(self: ParserMetrics) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    pub fn throughput_mbps(self: ParserMetrics) f64 {
        const elapsed = self.elapsed_ms();
        if (elapsed == 0) return 0.0;

        const mb = @as(f64, @floatFromInt(self.bytes_processed)) / (1024.0 * 1024.0);
        const seconds = @as(f64, @floatFromInt(elapsed)) / 1000.0;
        return mb / seconds;
    }

    pub fn commands_per_sec(self: ParserMetrics) f64 {
        const elapsed = self.elapsed_ms();
        if (elapsed == 0) return 0.0;

        const seconds = @as(f64, @floatFromInt(elapsed)) / 1000.0;
        return @as(f64, @floatFromInt(self.commands_parsed)) / seconds;
    }
};

/// Circular buffer for streaming parsing without allocation
pub const StreamBuffer = struct {
    data: []u8,
    start: usize = 0,
    len: usize = 0,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !StreamBuffer {
        return .{
            .data = try allocator.alloc(u8, capacity),
            .capacity = capacity,
        };
    }

    /// Add bytes to buffer
    pub fn append(self: *StreamBuffer, bytes: []const u8) !void {
        if (self.len + bytes.len > self.capacity) {
            return error.BufferFull;
        }

        const end = (self.start + self.len) % self.capacity;

        if (end + bytes.len <= self.capacity) {
            @memcpy(self.data[end .. end + bytes.len], bytes);
        } else {
            // Wrap around
            const first_part = self.capacity - end;
            @memcpy(self.data[end..], bytes[0..first_part]);
            @memcpy(self.data[0 .. bytes.len - first_part], bytes[first_part..]);
        }

        self.len += bytes.len;
    }

    /// Remove bytes from front
    pub fn consume(self: *StreamBuffer, count: usize) !void {
        if (count > self.len) {
            return error.BufferUnderflow;
        }

        self.start = (self.start + count) % self.capacity;
        self.len -= count;
    }

    /// Peek at bytes without consuming
    pub fn peek(self: StreamBuffer, offset: usize, len: usize) ![]u8 {
        if (offset + len > self.len) {
            return error.NotEnoughData;
        }

        // Simple case: no wrap
        const pos = self.start + offset;
        if (pos + len <= self.capacity) {
            return self.data[pos .. pos + len];
        }

        return error.WrappedData; // Caller must handle wrap case
    }

    /// Check if buffer has enough data
    pub fn available(self: StreamBuffer) usize {
        return self.len;
    }

    /// Clear buffer
    pub fn clear(self: *StreamBuffer) void {
        self.start = 0;
        self.len = 0;
    }

    /// Deinitialize
    pub fn deinit(self: StreamBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Parser state machine for efficient streaming
pub const ParseState = enum {
    waiting_for_command,
    reading_wcc,
    reading_order_code,
    reading_order_data,
    reading_text,
};

/// Optimized parser configuration
pub const ParserConfig = struct {
    buffer_size: usize = 4096,
    max_command_size: usize = 4096,
    use_streaming: bool = true,
    track_metrics: bool = true,

    /// Recommended config for throughput
    pub fn high_throughput() ParserConfig {
        return .{
            .buffer_size = 16384,
            .max_command_size = 8192,
            .use_streaming = true,
            .track_metrics = false,
        };
    }

    /// Recommended config for memory constrained
    pub fn low_memory() ParserConfig {
        return .{
            .buffer_size = 1024,
            .max_command_size = 1024,
            .use_streaming = true,
            .track_metrics = false,
        };
    }
};

/// Parser optimization benchmark
pub const ParserBenchmark = struct {
    allocator: std.mem.Allocator,
    metrics: ParserMetrics,

    pub fn init(allocator: std.mem.Allocator) ParserBenchmark {
        return .{
            .allocator = allocator,
            .metrics = .{ .start_time = std.time.milliTimestamp() },
        };
    }

    /// Record bytes processed
    pub fn record_bytes(self: *ParserBenchmark, count: u64) void {
        self.metrics.bytes_processed += count;
    }

    /// Record command parsed
    pub fn record_command(self: *ParserBenchmark) void {
        self.metrics.commands_parsed += 1;
    }

    /// Get current metrics
    pub fn get_metrics(self: ParserBenchmark) ParserMetrics {
        return self.metrics;
    }

    /// Print benchmark report
    pub fn report(self: ParserBenchmark) void {
        const metrics = self.metrics;
        std.debug.print("\n=== Parser Performance ===\n", .{});
        std.debug.print("Bytes processed: {}\n", .{metrics.bytes_processed});
        std.debug.print("Commands parsed: {}\n", .{metrics.commands_parsed});
        std.debug.print("Elapsed time: {} ms\n", .{metrics.elapsed_ms()});
        std.debug.print("Throughput: {d:.2} MB/s\n", .{metrics.throughput_mbps()});
        std.debug.print("Throughput: {d:.0} cmd/s\n", .{metrics.commands_per_sec()});
        std.debug.print("Allocations: {}\n", .{metrics.allocations});
    }
};

// Tests
test "parser_metrics: throughput calculation" {
    var metrics = ParserMetrics{
        .bytes_processed = 1_000_000, // 1 MB
        .commands_parsed = 1000,
        .start_time = std.time.milliTimestamp() - 1000, // 1 second ago
    };

    const throughput = metrics.throughput_mbps();
    try std.testing.expect(throughput > 0.9); // Should be ~1 MB/s
    try std.testing.expect(throughput < 1.1);
}

test "stream_buffer: init creates buffer" {
    var buffer = try StreamBuffer.init(std.testing.allocator, 256);
    defer buffer.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(@as(usize, 256), buffer.capacity);
}

test "stream_buffer: append stores data" {
    var buffer = try StreamBuffer.init(std.testing.allocator, 256);
    defer buffer.deinit(std.testing.allocator);

    try buffer.append("Hello");

    try std.testing.expectEqual(@as(usize, 5), buffer.len);
    try std.testing.expectEqual(@as(usize, 5), buffer.available());
}

test "stream_buffer: consume removes data" {
    var buffer = try StreamBuffer.init(std.testing.allocator, 256);
    defer buffer.deinit(std.testing.allocator);

    try buffer.append("HelloWorld");
    try buffer.consume(5);

    try std.testing.expectEqual(@as(usize, 5), buffer.len);
}

test "stream_buffer: peek reads without consuming" {
    var buffer = try StreamBuffer.init(std.testing.allocator, 256);
    defer buffer.deinit(std.testing.allocator);

    try buffer.append("Test");
    const peeked = try buffer.peek(0, 4);

    try std.testing.expectEqualSlices(u8, "Test", peeked);
    try std.testing.expectEqual(@as(usize, 4), buffer.len);
}

test "stream_buffer: clear resets buffer" {
    var buffer = try StreamBuffer.init(std.testing.allocator, 256);
    defer buffer.deinit(std.testing.allocator);

    try buffer.append("Data");
    buffer.clear();

    try std.testing.expectEqual(@as(usize, 0), buffer.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.start);
}

test "parser_config: high throughput config" {
    const config = ParserConfig.high_throughput();

    try std.testing.expectEqual(@as(usize, 16384), config.buffer_size);
    try std.testing.expect(config.use_streaming);
}

test "parser_config: low memory config" {
    const config = ParserConfig.low_memory();

    try std.testing.expectEqual(@as(usize, 1024), config.buffer_size);
    try std.testing.expect(config.use_streaming);
}

test "parser_benchmark: tracks metrics" {
    var bench = ParserBenchmark.init(std.testing.allocator);

    bench.record_bytes(1024);
    bench.record_bytes(512);
    bench.record_command();
    bench.record_command();

    const metrics = bench.get_metrics();
    try std.testing.expectEqual(@as(u64, 1536), metrics.bytes_processed);
    try std.testing.expectEqual(@as(u64, 2), metrics.commands_parsed);
}
