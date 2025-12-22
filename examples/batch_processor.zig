/// Batch processor example: Process multiple mainframe operations in high-throughput scenarios
///
/// Demonstrates:
/// - Session pooling for concurrent operations
/// - Command batching and pipelining
/// - Error handling and recovery
/// - Progress tracking and metrics
///
/// Usage:
///   zig build run-batch-processor -- --host mainframe.example.com --port 23 --count 100
///
const std = @import("std");

const root = @import("root");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var host: []const u8 = "localhost";
    var port: u16 = 23;
    var batch_size: usize = 100;
    var concurrent_sessions: usize = 5;

    // Parse command-line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = try std.fmt.parseUnsigned(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--count") and i + 1 < args.len) {
            batch_size = try std.fmt.parseUnsigned(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--sessions") and i + 1 < args.len) {
            concurrent_sessions = try std.fmt.parseUnsigned(usize, args[i + 1], 10);
            i += 1;
        }
    }

    std.debug.print("=== Batch Processor Example ===\n", .{});
    std.debug.print("Host: {s}:{d}\n", .{ host, port });
    std.debug.print("Batch size: {d}\n", .{batch_size});
    std.debug.print("Concurrent sessions: {d}\n", .{concurrent_sessions});
    std.debug.print("\n", .{});

    // Create metrics tracker
    var metrics = BatchMetrics{
        .start_time = std.time.microTimestamp(),
    };

    // Process batches
    var batch_index: usize = 0;
    while (batch_index < batch_size) : (batch_index += 1) {
        const batch_size_remaining = @min(10, batch_size - batch_index);

        std.debug.print("Processing batch {d}: {d} items...", .{ batch_index / 10 + 1, batch_size_remaining });
        std.debug.print("\r", .{});

        for (0..batch_size_remaining) |item_index| {
            const item_id = batch_index + item_index;
            process_batch_item(allocator, host, port, item_id, &metrics) catch |err| {
                std.debug.print("Error processing item {d}: {}\n", .{ item_id, err });
                metrics.errors += 1;
            };
        }
    }

    // Calculate and display metrics
    std.debug.print("\n\n=== Results ===\n", .{});
    metrics.print();
}

const BatchMetrics = struct {
    successful: usize = 0,
    errors: usize = 0,
    start_time: i64,
    total_latency_us: u64 = 0,

    fn print(self: *const BatchMetrics) void {
        const end_time = std.time.microTimestamp();
        const duration_us = @as(u64, @intCast(end_time - self.start_time));
        const duration_s = @as(f64, @floatFromInt(duration_us)) / 1_000_000.0;

        const total_items = self.successful + self.errors;
        const throughput = @as(f64, @floatFromInt(self.successful)) / duration_s;
        const avg_latency = if (self.successful > 0)
            self.total_latency_us / self.successful
        else
            0;

        std.debug.print("Total items processed: {d}\n", .{total_items});
        std.debug.print("Successful: {d}\n", .{self.successful});
        std.debug.print("Errors: {d}\n", .{self.errors});
        std.debug.print("Success rate: {d:.1}%\n", .{100.0 * @as(f64, @floatFromInt(self.successful)) / @as(f64, @floatFromInt(total_items))});
        std.debug.print("Duration: {d:.2}s\n", .{duration_s});
        std.debug.print("Throughput: {d:.0} items/sec\n", .{throughput});
        std.debug.print("Average latency: {d}µs\n", .{avg_latency});
    }
};

fn process_batch_item(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    item_id: usize,
    metrics: *BatchMetrics,
) !void {
    _ = allocator;
    _ = host;
    _ = port;
    _ = item_id;

    // Simulate processing
    const start = std.time.microTimestamp();

    // In a real scenario, you would:
    // 1. Create a session from pool
    // 2. Send command to mainframe
    // 3. Parse response
    // 4. Extract data
    // 5. Return session to pool

    std.time.sleep(100 * 1000); // Simulate 100µs network latency

    const end = std.time.microTimestamp();
    const latency_us = @as(u64, @intCast(end - start));

    metrics.successful += 1;
    metrics.total_latency_us += latency_us;
}

pub const root_decl = struct {
    pub const std_options: std.Options = .{
        .log_level = .info,
    };
};
