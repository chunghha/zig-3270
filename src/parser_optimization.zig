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

/// Incremental parser for handling large datasets in chunks
/// Supports resume capability for partial frames
pub const IncrementalParser = struct {
    allocator: std.mem.Allocator,
    state: ParseState = .waiting_for_command,
    buffer: StreamBuffer,
    config: ParserConfig,
    metrics: ParserMetrics,
    pending_bytes: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, config: ParserConfig) !IncrementalParser {
        var buffer = try StreamBuffer.init(allocator, config.buffer_size);
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .config = config,
            .metrics = .{ .start_time = std.time.milliTimestamp() },
        };
    }

    pub fn deinit(self: *IncrementalParser) void {
        self.buffer.deinit(self.allocator);
    }

    /// Add chunk of data to parser
    pub fn add_chunk(self: *IncrementalParser, data: []const u8) !void {
        try self.buffer.append(data);
        self.metrics.bytes_processed += data.len;
    }

    /// Try to parse next command from buffer
    /// Returns true if a complete command was parsed, false if incomplete
    pub fn parse_next(self: *IncrementalParser) !bool {
        if (self.buffer.available() < 1) {
            return false; // Need more data
        }

        // Peek at command code
        const cmd_code = try self.buffer.peek(0, 1);
        const command_code = cmd_code[0];

        // Different command codes have different sizes
        const min_size: usize = switch (command_code) {
            0xF1 => 2, // Write
            0xF5 => 2, // Erase Write
            0xF3 => 2, // Read
            0x6B => 3, // WSF
            else => 2,
        };

        if (self.buffer.available() < min_size) {
            return false; // Incomplete command
        }

        // Consume the command bytes
        try self.buffer.consume(min_size);
        self.metrics.commands_parsed += 1;
        self.pending_bytes = 0;

        return true;
    }

    /// Parse all available complete commands, leave incomplete data
    pub fn parse_available(self: *IncrementalParser) !u64 {
        var parsed_count: u64 = 0;

        while (try self.parse_next()) {
            parsed_count += 1;
        }

        return parsed_count;
    }

    /// Get current parser metrics
    pub fn get_metrics(self: IncrementalParser) ParserMetrics {
        return self.metrics;
    }

    /// Check if parser is waiting for more data
    pub fn is_waiting(self: IncrementalParser) bool {
        return self.buffer.available() > 0 and self.buffer.available() < 2;
    }

    /// Get amount of pending data in buffer
    pub fn pending(self: IncrementalParser) usize {
        return self.buffer.available();
    }

    /// Reset parser state (for error recovery)
    pub fn reset(self: *IncrementalParser) void {
        self.buffer.clear();
        self.state = .waiting_for_command;
        self.pending_bytes = 0;
    }
};

/// Large dataset handler for frames >10KB
pub const LargeDatasetHandler = struct {
    allocator: std.mem.Allocator,
    parser: IncrementalParser,
    chunk_size: usize = 4096,
    max_frame_size: usize = 65536,
    total_processed: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, chunk_size: usize) !LargeDatasetHandler {
        const config = ParserConfig{
            .buffer_size = 16384,
            .max_command_size = 8192,
            .use_streaming = true,
            .track_metrics = true,
        };

        var parser = try IncrementalParser.init(allocator, config);

        return .{
            .allocator = allocator,
            .parser = parser,
            .chunk_size = chunk_size,
            .max_frame_size = 65536,
        };
    }

    pub fn deinit(self: *LargeDatasetHandler) void {
        self.parser.deinit();
    }

    /// Process a large frame in chunks
    pub fn process_large_frame(self: *LargeDatasetHandler, frame: []const u8) !u64 {
        if (frame.len > self.max_frame_size) {
            return error.FrameTooLarge;
        }

        var processed: u64 = 0;
        var offset: usize = 0;

        while (offset < frame.len) {
            const chunk_end = @min(offset + self.chunk_size, frame.len);
            const chunk = frame[offset..chunk_end];

            try self.parser.add_chunk(chunk);
            const parsed = try self.parser.parse_available();
            processed += parsed;
            offset = chunk_end;
        }

        self.total_processed += frame.len;
        return processed;
    }

    /// Get overall statistics
    pub fn get_stats(self: LargeDatasetHandler) struct {
        total_bytes: u64,
        total_commands: u64,
        avg_command_size: f64,
        processing_rate_mbps: f64,
    } {
        const metrics = self.parser.get_metrics();
        const total = self.total_processed;
        const cmd_count = metrics.commands_parsed;

        const avg_size: f64 = if (cmd_count > 0)
            @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(cmd_count))
        else
            0.0;

        return .{
            .total_bytes = total,
            .total_commands = cmd_count,
            .avg_command_size = avg_size,
            .processing_rate_mbps = metrics.throughput_mbps(),
        };
    }
};

// Tests for incremental parsing
test "incremental_parser: init creates parser" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try std.testing.expectEqual(@as(u64, 0), parser.metrics.bytes_processed);
    try std.testing.expectEqual(@as(u64, 0), parser.metrics.commands_parsed);
}

test "incremental_parser: add chunk increments bytes" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try parser.add_chunk("Hello");
    try parser.add_chunk("World");

    try std.testing.expectEqual(@as(u64, 10), parser.metrics.bytes_processed);
}

test "incremental_parser: parse incomplete command returns false" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try parser.add_chunk("\xF1");

    const result = try parser.parse_next();
    try std.testing.expect(!result);
}

test "incremental_parser: parse complete command returns true" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try parser.add_chunk("\xF1\x00");

    const result = try parser.parse_next();
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u64, 1), parser.metrics.commands_parsed);
}

test "incremental_parser: parse all available" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try parser.add_chunk("\xF1\x00\xF5\x00\xF3\x00");

    const parsed = try parser.parse_available();
    try std.testing.expectEqual(@as(u64, 3), parsed);
}

test "incremental_parser: reset clears state" {
    const config = ParserConfig.high_throughput();
    var parser = try IncrementalParser.init(std.testing.allocator, config);
    defer parser.deinit();

    try parser.add_chunk("data");
    parser.reset();

    try std.testing.expectEqual(@as(usize, 0), parser.pending());
}

test "large_dataset_handler: init creates handler" {
    var handler = try LargeDatasetHandler.init(std.testing.allocator, 1024);
    defer handler.deinit();

    try std.testing.expectEqual(@as(usize, 4096), handler.chunk_size);
}

test "large_dataset_handler: process small frame" {
    var handler = try LargeDatasetHandler.init(std.testing.allocator, 256);
    defer handler.deinit();

    const frame = "\xF1\x00\xF5\x00\xF3\x00";
    const parsed = try handler.process_large_frame(frame);

    try std.testing.expectEqual(@as(u64, 3), parsed);
}

test "large_dataset_handler: process large frame" {
    var handler = try LargeDatasetHandler.init(std.testing.allocator, 512);
    defer handler.deinit();

    // Create large frame with many commands
    var frame_buffer: [4096]u8 = undefined;
    var offset: usize = 0;

    // Add 1000 simple commands (2 bytes each)
    for (0..1000) |i| {
        if (offset + 2 <= frame_buffer.len) {
            frame_buffer[offset] = if (i % 3 == 0) 0xF1 else if (i % 3 == 1) 0xF5 else 0xF3;
            frame_buffer[offset + 1] = 0x00;
            offset += 2;
        }
    }

    const frame = frame_buffer[0..offset];
    const parsed = try handler.process_large_frame(frame);

    try std.testing.expectEqual(@as(u64, 1000), parsed);
}

test "large_dataset_handler: get stats" {
    var handler = try LargeDatasetHandler.init(std.testing.allocator, 256);
    defer handler.deinit();

    const frame = "\xF1\x00\xF5\x00";
    _ = try handler.process_large_frame(frame);

    const stats = handler.get_stats();
    try std.testing.expectEqual(@as(u64, 4), stats.total_bytes);
    try std.testing.expectEqual(@as(u64, 2), stats.total_commands);
    try std.testing.expect(stats.avg_command_size > 0);
}
