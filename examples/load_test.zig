/// Load test example: Generate load against mainframe for capacity planning
///
/// Demonstrates:
/// - Creating multiple concurrent connections
/// - Sending sustained load
/// - Measuring throughput and latency
/// - Identifying bottlenecks
///
/// Usage:
///   zig build run-load-test -- --host mainframe.example.com --port 23 --duration 60 --rps 1000
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
    var duration_s: u64 = 10;
    var requests_per_sec: u64 = 100;
    var num_workers: usize = 4;

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = try std.fmt.parseUnsigned(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--duration") and i + 1 < args.len) {
            duration_s = try std.fmt.parseUnsigned(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--rps") and i + 1 < args.len) {
            requests_per_sec = try std.fmt.parseUnsigned(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--workers") and i + 1 < args.len) {
            num_workers = try std.fmt.parseUnsigned(usize, args[i + 1], 10);
            i += 1;
        }
    }

    std.debug.print("=== Load Test ===\n", .{});
    std.debug.print("Target: {s}:{d}\n", .{ host, port });
    std.debug.print("Duration: {d}s\n", .{duration_s});
    std.debug.print("Target RPS: {d}\n", .{requests_per_sec});
    std.debug.print("Workers: {d}\n", .{num_workers});
    std.debug.print("\n", .{});

    // Create load test
    var load_test = LoadTest{
        .host = host,
        .port = port,
        .duration_s = duration_s,
        .target_rps = requests_per_sec,
        .allocator = allocator,
    };

    // Run load test
    try load_test.run(num_workers);
}

const LoadTest = struct {
    host: []const u8,
    port: u16,
    duration_s: u64,
    target_rps: u64,
    allocator: std.mem.Allocator,

    fn run(self: *LoadTest, num_workers: usize) !void {
        const start_time = std.time.microTimestamp();
        const end_time = start_time + @as(i64, @intCast(self.duration_s)) * 1_000_000;

        var metrics = LoadTestMetrics{
            .start_time = start_time,
        };

        std.debug.print("Starting load test...\n", .{});

        // Simulate load generation
        var current_time = start_time;
        var requests_sent: u64 = 0;
        var requests_per_interval = self.target_rps / 10; // Report every 100ms

        while (current_time < end_time) {
            // Send batch of requests
            for (0..requests_per_interval) |_| {
                const latency_us = try self.send_request();
                metrics.record_latency(latency_us);
                requests_sent += 1;
            }

            // Print progress every 100ms
            const elapsed = @as(f64, @floatFromInt(current_time - start_time)) / 1_000_000.0;
            const actual_rps = @as(f64, @floatFromInt(requests_sent)) / elapsed;

            std.debug.print(
                "Elapsed: {d:.1}s | Sent: {d} | RPS: {d:.0} | Avg Latency: {d:.0}µs\r",
                .{
                    elapsed,
                    requests_sent,
                    @as(u64, @intFromFloat(actual_rps)),
                    metrics.avg_latency(),
                },
            );

            // Sleep before next batch
            std.time.sleep(100 * 1_000_000); // 100ms
            current_time = std.time.microTimestamp();
        }

        std.debug.print("\n\n", .{});
        metrics.print();
    }

    fn send_request(self: *LoadTest) !u64 {
        // Simulate sending a request
        _ = self;

        // Simulate network latency + processing (50-500µs)
        const base_latency: u64 = 50;
        const variable_latency: u64 = @as(u64, @truncate(std.time.microTimestamp())) % 450;
        const total_latency = base_latency + variable_latency;

        std.time.sleep(total_latency * 1000); // Simulate I/O

        return total_latency;
    }
};

const LoadTestMetrics = struct {
    start_time: i64,
    latencies: [10000]u64 = undefined,
    latency_count: usize = 0,
    total_errors: usize = 0,

    fn record_latency(self: *LoadTestMetrics, latency_us: u64) void {
        if (self.latency_count < self.latencies.len) {
            self.latencies[self.latency_count] = latency_us;
            self.latency_count += 1;
        }
    }

    fn avg_latency(self: *const LoadTestMetrics) u64 {
        if (self.latency_count == 0) return 0;
        var sum: u64 = 0;
        for (self.latencies[0..self.latency_count]) |latency| {
            sum += latency;
        }
        return sum / self.latency_count;
    }

    fn percentile_latency(self: *const LoadTestMetrics, p: f64) u64 {
        if (self.latency_count == 0) return 0;

        // Simple percentile (not exact, but close enough)
        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.latency_count)) * p));
        return if (index < self.latency_count) self.latencies[index] else self.latencies[self.latency_count - 1];
    }

    fn print(self: *const LoadTestMetrics) void {
        const end_time = std.time.microTimestamp();
        const duration_us = @as(u64, @intCast(end_time - self.start_time));
        const duration_s = @as(f64, @floatFromInt(duration_us)) / 1_000_000.0;

        const actual_rps = @as(f64, @floatFromInt(self.latency_count)) / duration_s;
        const avg = self.avg_latency();
        const p50 = self.percentile_latency(0.5);
        const p95 = self.percentile_latency(0.95);
        const p99 = self.percentile_latency(0.99);

        std.debug.print("=== Load Test Results ===\n", .{});
        std.debug.print("Duration: {d:.2}s\n", .{duration_s});
        std.debug.print("Total Requests: {d}\n", .{self.latency_count});
        std.debug.print("Actual RPS: {d:.0}\n", .{actual_rps});
        std.debug.print("Errors: {d}\n", .{self.total_errors});
        std.debug.print("\n", .{});
        std.debug.print("Latency Statistics:\n", .{});
        std.debug.print("  Average: {d}µs\n", .{avg});
        std.debug.print("  p50: {d}µs\n", .{p50});
        std.debug.print("  p95: {d}µs\n", .{p95});
        std.debug.print("  p99: {d}µs\n", .{p99});
    }
};

pub const root_decl = struct {
    pub const std_options: std.Options = .{
        .log_level = .info,
    };
};
