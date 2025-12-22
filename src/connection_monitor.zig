const std = @import("std");

/// Connection health monitoring with metrics and diagnostics
/// Tracks per-connection performance, error rates, and provides health checks
pub const ConnectionMonitor = struct {
    /// Per-connection metrics snapshot
    pub const Metrics = struct {
        host: []const u8,
        port: u16,
        bytes_sent: u64 = 0,
        bytes_received: u64 = 0,
        commands_sent: u64 = 0,
        responses_received: u64 = 0,
        error_count: u32 = 0,
        connection_uptime_ms: i64 = 0,
        last_activity_ms: i64 = 0,
        response_time_min_ms: u32 = std.math.maxInt(u32),
        response_time_max_ms: u32 = 0,
        response_time_total_ms: u64 = 0,
        connection_count: u32 = 1,
        reconnect_count: u32 = 0,

        pub fn avg_response_time_ms(self: Metrics) f64 {
            if (self.responses_received == 0) return 0;
            return @as(f64, @floatFromInt(self.response_time_total_ms)) / @as(f64, @floatFromInt(self.responses_received));
        }

        pub fn error_rate(self: Metrics) f64 {
            const total = self.commands_sent + self.error_count;
            if (total == 0) return 0;
            return @as(f64, @floatFromInt(self.error_count)) / @as(f64, @floatFromInt(total));
        }

        pub fn throughput_bytes_per_sec(self: Metrics) f64 {
            if (self.connection_uptime_ms == 0) return 0;
            const total_bytes = self.bytes_sent + self.bytes_received;
            const uptime_sec = @as(f64, @floatFromInt(self.connection_uptime_ms)) / 1000.0;
            return @as(f64, @floatFromInt(total_bytes)) / uptime_sec;
        }
    };

    /// Health check result
    pub const HealthStatus = enum {
        healthy,
        degraded,
        unhealthy,
    };

    /// Health check thresholds
    pub const HealthThresholds = struct {
        max_error_rate: f64 = 0.05, // 5% error rate
        max_response_time_ms: u32 = 5000, // 5 seconds
        max_uptime_without_activity_ms: i64 = 30000, // 30 seconds idle
        min_throughput_bytes_per_sec: f64 = 100, // 100 bytes/sec minimum
    };

    /// Health check alert
    pub const HealthAlert = struct {
        status: HealthStatus,
        reasons: std.ArrayList([]const u8),
        timestamp_ms: i64,

        pub fn deinit(self: *HealthAlert, allocator: std.mem.Allocator) void {
            for (self.reasons.items) |reason| {
                allocator.free(reason);
            }
            self.reasons.deinit();
        }
    };

    allocator: std.mem.Allocator,
    metrics: std.StringHashMap(Metrics),
    thresholds: HealthThresholds,
    connection_start_times: std.StringHashMap(i64),

    pub fn init(allocator: std.mem.Allocator) ConnectionMonitor {
        return .{
            .allocator = allocator,
            .metrics = std.StringHashMap(Metrics).init(allocator),
            .thresholds = .{},
            .connection_start_times = std.StringHashMap(i64).init(allocator),
        };
    }

    pub fn deinit(self: *ConnectionMonitor) void {
        var iter = self.metrics.keyIterator();
        while (iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.metrics.deinit();

        var iter2 = self.connection_start_times.keyIterator();
        while (iter2.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.connection_start_times.deinit();
    }

    /// Register a new connection
    pub fn register_connection(self: *ConnectionMonitor, host: []const u8, port: u16) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        const host_copy = try self.allocator.dupe(u8, host);
        const key_copy = try self.allocator.dupe(u8, key);

        try self.metrics.put(key_copy, .{
            .host = host_copy,
            .port = port,
        });

        try self.connection_start_times.put(key_copy, std.time.milliTimestamp());
    }

    /// Record bytes sent
    pub fn record_bytes_sent(self: *ConnectionMonitor, host: []const u8, port: u16, bytes: u64) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.bytes_sent += bytes;
            metrics.last_activity_ms = std.time.milliTimestamp();
        }
    }

    /// Record bytes received
    pub fn record_bytes_received(self: *ConnectionMonitor, host: []const u8, port: u16, bytes: u64) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.bytes_received += bytes;
            metrics.last_activity_ms = std.time.milliTimestamp();
        }
    }

    /// Record command sent
    pub fn record_command_sent(self: *ConnectionMonitor, host: []const u8, port: u16) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.commands_sent += 1;
            metrics.last_activity_ms = std.time.milliTimestamp();
        }
    }

    /// Record response received with response time
    pub fn record_response_received(self: *ConnectionMonitor, host: []const u8, port: u16, response_time_ms: u32) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.responses_received += 1;
            metrics.response_time_min_ms = @min(metrics.response_time_min_ms, response_time_ms);
            metrics.response_time_max_ms = @max(metrics.response_time_max_ms, response_time_ms);
            metrics.response_time_total_ms += response_time_ms;
            metrics.last_activity_ms = std.time.milliTimestamp();
        }
    }

    /// Record error
    pub fn record_error(self: *ConnectionMonitor, host: []const u8, port: u16) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.error_count += 1;
            metrics.last_activity_ms = std.time.milliTimestamp();
        }
    }

    /// Record reconnection
    pub fn record_reconnection(self: *ConnectionMonitor, host: []const u8, port: u16) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            metrics.reconnect_count += 1;
            metrics.connection_count += 1;
            if (self.connection_start_times.getPtr(key)) |start_time| {
                start_time.* = std.time.milliTimestamp();
            }
        }
    }

    /// Get current metrics for a connection
    pub fn get_metrics(self: *ConnectionMonitor, host: []const u8, port: u16) !?Metrics {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ host, port });
        defer self.allocator.free(key);

        if (self.metrics.getPtr(key)) |metrics| {
            // Update connection uptime
            if (self.connection_start_times.get(key)) |start_time| {
                metrics.connection_uptime_ms = std.time.milliTimestamp() - start_time;
            }
            return metrics.*;
        }

        return null;
    }

    /// Perform health check on connection
    pub fn check_health(self: *ConnectionMonitor, host: []const u8, port: u16) !HealthAlert {
        var alert = HealthAlert{
            .status = .healthy,
            .reasons = std.ArrayList([]const u8).init(self.allocator),
            .timestamp_ms = std.time.milliTimestamp(),
        };

        if (try self.get_metrics(host, port)) |metrics| {
            // Check error rate
            if (metrics.error_rate() > self.thresholds.max_error_rate) {
                alert.status = .unhealthy;
                const reason = try std.fmt.allocPrint(self.allocator, "High error rate: {d:.2}%", .{metrics.error_rate() * 100});
                try alert.reasons.append(reason);
            }

            // Check response time
            if (metrics.response_time_max_ms > self.thresholds.max_response_time_ms) {
                if (alert.status == .healthy) {
                    alert.status = .degraded;
                }
                const reason = try std.fmt.allocPrint(self.allocator, "High response time: {d}ms", .{metrics.response_time_max_ms});
                try alert.reasons.append(reason);
            }

            // Check idle time
            const now = std.time.milliTimestamp();
            const idle_time = now - metrics.last_activity_ms;
            if (idle_time > self.thresholds.max_uptime_without_activity_ms) {
                if (alert.status == .healthy) {
                    alert.status = .degraded;
                }
                const reason = try std.fmt.allocPrint(self.allocator, "Idle for {d}ms", .{idle_time});
                try alert.reasons.append(reason);
            }

            // Check throughput
            if (metrics.connection_uptime_ms > 0 and metrics.throughput_bytes_per_sec() < self.thresholds.min_throughput_bytes_per_sec) {
                if (alert.status == .healthy) {
                    alert.status = .degraded;
                }
                const reason = try std.fmt.allocPrint(self.allocator, "Low throughput: {d:.2} bytes/sec", .{metrics.throughput_bytes_per_sec()});
                try alert.reasons.append(reason);
            }
        }

        return alert;
    }

    /// Export metrics as JSON string
    pub fn export_metrics_json(self: *ConnectionMonitor, host: []const u8, port: u16) !?[]u8 {
        if (try self.get_metrics(host, port)) |metrics| {
            return try std.fmt.allocPrint(self.allocator,
                \\{{"host":"{s}","port":{d},"bytes_sent":{d},"bytes_received":{d},"commands_sent":{d},"responses_received":{d},"error_count":{d},"uptime_ms":{d},"avg_response_ms":{d:.2},"error_rate":{d:.4},"throughput_bps":{d:.2}}}
            , .{
                metrics.host,
                metrics.port,
                metrics.bytes_sent,
                metrics.bytes_received,
                metrics.commands_sent,
                metrics.responses_received,
                metrics.error_count,
                metrics.connection_uptime_ms,
                metrics.avg_response_time_ms(),
                metrics.error_rate(),
                metrics.throughput_bytes_per_sec(),
            });
        }
        return null;
    }

    /// Set custom health thresholds
    pub fn set_thresholds(self: *ConnectionMonitor, thresholds: HealthThresholds) void {
        self.thresholds = thresholds;
    }
};

// Tests
test "ConnectionMonitor initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    const metrics = try monitor.get_metrics("127.0.0.1", 3270);
    try std.testing.expect(metrics != null);
    try std.testing.expectEqualStrings(metrics.?.host, "127.0.0.1");
    try std.testing.expectEqual(metrics.?.port, 3270);
}

test "ConnectionMonitor record bytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_bytes_sent("127.0.0.1", 3270, 100);
    try monitor.record_bytes_received("127.0.0.1", 3270, 200);

    const metrics = try monitor.get_metrics("127.0.0.1", 3270);
    try std.testing.expectEqual(metrics.?.bytes_sent, 100);
    try std.testing.expectEqual(metrics.?.bytes_received, 200);
}

test "ConnectionMonitor response time tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_response_received("127.0.0.1", 3270, 100);
    try monitor.record_response_received("127.0.0.1", 3270, 200);
    try monitor.record_response_received("127.0.0.1", 3270, 150);

    const metrics = try monitor.get_metrics("127.0.0.1", 3270);
    try std.testing.expectEqual(metrics.?.response_time_min_ms, 100);
    try std.testing.expectEqual(metrics.?.response_time_max_ms, 200);
    try std.testing.expect(metrics.?.avg_response_time_ms() > 140.0 and metrics.?.avg_response_time_ms() < 160.0);
}

test "ConnectionMonitor error rate calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_command_sent("127.0.0.1", 3270);
    try monitor.record_command_sent("127.0.0.1", 3270);
    try monitor.record_error("127.0.0.1", 3270);

    const metrics = try monitor.get_metrics("127.0.0.1", 3270);
    const expected_rate = 1.0 / 3.0;
    try std.testing.expect(@abs(metrics.?.error_rate() - expected_rate) < 0.01);
}

test "ConnectionMonitor health check - healthy status" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_command_sent("127.0.0.1", 3270);
    try monitor.record_response_received("127.0.0.1", 3270, 100);

    var alert = try monitor.check_health("127.0.0.1", 3270);
    defer alert.deinit(allocator);

    try std.testing.expectEqual(alert.status, ConnectionMonitor.HealthStatus.healthy);
    try std.testing.expectEqual(alert.reasons.items.len, 0);
}

test "ConnectionMonitor health check - high error rate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    for (0..10) |_| {
        try monitor.record_command_sent("127.0.0.1", 3270);
        try monitor.record_error("127.0.0.1", 3270);
    }

    var alert = try monitor.check_health("127.0.0.1", 3270);
    defer alert.deinit(allocator);

    try std.testing.expectEqual(alert.status, ConnectionMonitor.HealthStatus.unhealthy);
    try std.testing.expect(alert.reasons.items.len > 0);
}

test "ConnectionMonitor metrics export JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_bytes_sent("127.0.0.1", 3270, 100);
    try monitor.record_bytes_received("127.0.0.1", 3270, 200);

    const json = try monitor.export_metrics_json("127.0.0.1", 3270);
    try std.testing.expect(json != null);
    defer allocator.free(json.?);
    try std.testing.expect(std.mem.containsAtLeast(u8, json.?, 1, "127.0.0.1"));
}

test "ConnectionMonitor reconnection tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_reconnection("127.0.0.1", 3270);
    try monitor.record_reconnection("127.0.0.1", 3270);

    const metrics = try monitor.get_metrics("127.0.0.1", 3270);
    try std.testing.expectEqual(metrics.?.reconnect_count, 2);
    try std.testing.expectEqual(metrics.?.connection_count, 3);
}

test "ConnectionMonitor custom thresholds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    const custom_thresholds: ConnectionMonitor.HealthThresholds = .{
        .max_error_rate = 0.1,
        .max_response_time_ms = 1000,
    };
    monitor.set_thresholds(custom_thresholds);

    try monitor.register_connection("127.0.0.1", 3270);
    for (0..9) |_| {
        try monitor.record_command_sent("127.0.0.1", 3270);
        try monitor.record_error("127.0.0.1", 3270);
    }

    var alert = try monitor.check_health("127.0.0.1", 3270);
    defer alert.deinit(allocator);

    // With 9 errors out of 18 commands (50%), should still be unhealthy
    try std.testing.expectEqual(alert.status, ConnectionMonitor.HealthStatus.unhealthy);
}
