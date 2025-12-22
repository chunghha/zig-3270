/// Operational monitoring and metrics export for production visibility.
/// Supports Prometheus format, JSON export, and real-time metrics tracking.
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Per-session statistics
pub const SessionMetrics = struct {
    session_id: u32,
    commands_processed: u64 = 0,
    commands_failed: u64 = 0,
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    average_latency_ms: u32 = 0,
    peak_latency_ms: u32 = 0,
    errors: u64 = 0,
    start_time: u64 = 0,

    pub fn duration_seconds(self: SessionMetrics) i64 {
        if (self.start_time == 0) return 0;
        const current: i64 = @intCast(std.time.timestamp());
        const start: i64 = @intCast(self.start_time);
        return current - start;
    }

    pub fn throughput_commands_per_second(self: SessionMetrics) f64 {
        const duration = self.duration_seconds();
        if (duration == 0) return 0;
        return @as(f64, @floatFromInt(self.commands_processed)) / @as(f64, @floatFromInt(duration));
    }

    pub fn throughput_mb_per_second(self: SessionMetrics) f64 {
        const duration = self.duration_seconds();
        if (duration == 0) return 0;
        const mb = @as(f64, @floatFromInt(self.bytes_sent + self.bytes_received)) / (1024.0 * 1024.0);
        return mb / @as(f64, @floatFromInt(duration));
    }

    pub fn error_rate_percent(self: SessionMetrics) f64 {
        if (self.commands_processed == 0) return 0;
        return (@as(f64, @floatFromInt(self.commands_failed)) / @as(f64, @floatFromInt(self.commands_processed))) * 100.0;
    }
};

/// System-wide metrics
pub const SystemMetrics = struct {
    allocator: Allocator,
    total_connections: u64 = 0,
    active_connections: u32 = 0,
    total_sessions: u64 = 0,
    active_sessions: u32 = 0,
    total_commands: u64 = 0,
    failed_commands: u64 = 0,
    total_bytes_sent: u64 = 0,
    total_bytes_received: u64 = 0,
    peak_active_connections: u32 = 0,
    peak_active_sessions: u32 = 0,
    uptime_seconds: u64 = 0,
    last_error: ?[]const u8 = null,

    pub fn init(allocator: Allocator) !SystemMetrics {
        return SystemMetrics{
            .allocator = allocator,
        };
    }

    pub fn record_connection(self: *SystemMetrics) void {
        self.total_connections += 1;
        self.active_connections += 1;
        if (self.active_connections > self.peak_active_connections) {
            self.peak_active_connections = self.active_connections;
        }
    }

    pub fn record_disconnection(self: *SystemMetrics) void {
        if (self.active_connections > 0) {
            self.active_connections -= 1;
        }
    }

    pub fn record_session_start(self: *SystemMetrics) void {
        self.total_sessions += 1;
        self.active_sessions += 1;
        if (self.active_sessions > self.peak_active_sessions) {
            self.peak_active_sessions = self.active_sessions;
        }
    }

    pub fn record_session_end(self: *SystemMetrics) void {
        if (self.active_sessions > 0) {
            self.active_sessions -= 1;
        }
    }

    pub fn record_command(self: *SystemMetrics, success: bool) void {
        self.total_commands += 1;
        if (!success) {
            self.failed_commands += 1;
        }
    }

    pub fn record_data_sent(self: *SystemMetrics, bytes: u64) void {
        self.total_bytes_sent += bytes;
    }

    pub fn record_data_received(self: *SystemMetrics, bytes: u64) void {
        self.total_bytes_received += bytes;
    }

    pub fn command_success_rate(self: SystemMetrics) f64 {
        if (self.total_commands == 0) return 100.0;
        return ((@as(f64, @floatFromInt(self.total_commands)) - @as(f64, @floatFromInt(self.failed_commands))) / @as(f64, @floatFromInt(self.total_commands))) * 100.0;
    }
};

/// Prometheus metrics formatter
pub const PrometheusExporter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) PrometheusExporter {
        return PrometheusExporter{
            .allocator = allocator,
        };
    }

    pub fn export_system_metrics(
        self: PrometheusExporter,
        metrics: SystemMetrics,
    ) ![]u8 {
        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 512);
        defer buffer.deinit(self.allocator);

        var writer = buffer.writer(self.allocator);

        // Connection metrics
        try writer.print("# HELP tn3270_active_connections Active TCP connections\n", .{});
        try writer.print("# TYPE tn3270_active_connections gauge\n", .{});
        try writer.print("tn3270_active_connections {}\n", .{metrics.active_connections});

        // Session metrics
        try writer.print("# HELP tn3270_active_sessions Active user sessions\n", .{});
        try writer.print("# TYPE tn3270_active_sessions gauge\n", .{});
        try writer.print("tn3270_active_sessions {}\n", .{metrics.active_sessions});

        // Command metrics
        try writer.print("# HELP tn3270_total_commands Total commands processed\n", .{});
        try writer.print("# TYPE tn3270_total_commands counter\n", .{});
        try writer.print("tn3270_total_commands {}\n", .{metrics.total_commands});

        try writer.print("# HELP tn3270_failed_commands Failed commands\n", .{});
        try writer.print("# TYPE tn3270_failed_commands counter\n", .{});
        try writer.print("tn3270_failed_commands {}\n", .{metrics.failed_commands});

        // Data metrics
        try writer.print("# HELP tn3270_bytes_sent Total bytes sent\n", .{});
        try writer.print("# TYPE tn3270_bytes_sent counter\n", .{});
        try writer.print("tn3270_bytes_sent {}\n", .{metrics.total_bytes_sent});

        try writer.print("# HELP tn3270_bytes_received Total bytes received\n", .{});
        try writer.print("# TYPE tn3270_bytes_received counter\n", .{});
        try writer.print("tn3270_bytes_received {}\n", .{metrics.total_bytes_received});

        // Peak metrics
        try writer.print("# HELP tn3270_peak_connections Peak concurrent connections\n", .{});
        try writer.print("# TYPE tn3270_peak_connections gauge\n", .{});
        try writer.print("tn3270_peak_connections {}\n", .{metrics.peak_active_connections});

        return buffer.toOwnedSlice(self.allocator);
    }

    pub fn export_session_metrics(
        self: PrometheusExporter,
        session: SessionMetrics,
    ) ![]u8 {
        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer buffer.deinit(self.allocator);

        var writer = buffer.writer(self.allocator);

        try writer.print("# HELP tn3270_session_commands Commands processed in session\n", .{});
        try writer.print("# TYPE tn3270_session_commands counter\n", .{});
        try writer.print("tn3270_session_commands{{session_id=\"{}\"}} {}\n", .{ session.session_id, session.commands_processed });

        try writer.print("# HELP tn3270_session_bytes_sent Bytes sent in session\n", .{});
        try writer.print("# TYPE tn3270_session_bytes_sent counter\n", .{});
        try writer.print("tn3270_session_bytes_sent{{session_id=\"{}\"}} {}\n", .{ session.session_id, session.bytes_sent });

        try writer.print("# HELP tn3270_session_latency_ms Average latency in session\n", .{});
        try writer.print("# TYPE tn3270_session_latency_ms gauge\n", .{});
        try writer.print("tn3270_session_latency_ms{{session_id=\"{}\"}} {}\n", .{ session.session_id, session.average_latency_ms });

        return buffer.toOwnedSlice(self.allocator);
    }
};

/// JSON metrics exporter
pub const JSONExporter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) JSONExporter {
        return JSONExporter{
            .allocator = allocator,
        };
    }

    pub fn export_system_metrics(
        self: JSONExporter,
        metrics: SystemMetrics,
    ) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            \\{{
            \\  "active_connections": {},
            \\  "active_sessions": {},
            \\  "total_commands": {},
            \\  "failed_commands": {},
            \\  "success_rate_percent": {d:.2},
            \\  "total_bytes_sent": {},
            \\  "total_bytes_received": {},
            \\  "peak_connections": {},
            \\  "peak_sessions": {}
            \\}}
        ,
            .{
                metrics.active_connections,
                metrics.active_sessions,
                metrics.total_commands,
                metrics.failed_commands,
                metrics.command_success_rate(),
                metrics.total_bytes_sent,
                metrics.total_bytes_received,
                metrics.peak_active_connections,
                metrics.peak_active_sessions,
            },
        );
    }

    pub fn export_session_metrics(
        self: JSONExporter,
        session: SessionMetrics,
    ) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            \\{{
            \\  "session_id": {},
            \\  "commands_processed": {},
            \\  "bytes_sent": {},
            \\  "bytes_received": {},
            \\  "throughput_cps": {d:.2},
            \\  "throughput_mbps": {d:.2},
            \\  "error_rate_percent": {d:.2},
            \\  "average_latency_ms": {}
            \\}}
        ,
            .{
                session.session_id,
                session.commands_processed,
                session.bytes_sent,
                session.bytes_received,
                session.throughput_commands_per_second(),
                session.throughput_mb_per_second(),
                session.error_rate_percent(),
                session.average_latency_ms,
            },
        );
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "SessionMetrics calculates throughput correctly" {
    const metrics = SessionMetrics{
        .session_id = 1,
        .commands_processed = 100,
        .bytes_sent = 10000,
        .bytes_received = 5000,
        .average_latency_ms = 50,
        .commands_failed = 5,
    };

    // Test error rate calculation
    const error_rate = metrics.error_rate_percent();
    try testing.expect(error_rate > 4.0 and error_rate < 6.0);
}

test "SessionMetrics tracks peak latency" {
    const metrics = SessionMetrics{
        .session_id = 1,
        .peak_latency_ms = 500,
    };

    try testing.expectEqual(@as(u32, 500), metrics.peak_latency_ms);
}

test "SystemMetrics tracks connections" {
    const allocator = testing.allocator;
    var metrics = try SystemMetrics.init(allocator);

    metrics.record_connection();
    metrics.record_connection();
    try testing.expectEqual(@as(u32, 2), metrics.active_connections);
    try testing.expectEqual(@as(u32, 2), metrics.peak_active_connections);

    metrics.record_disconnection();
    try testing.expectEqual(@as(u32, 1), metrics.active_connections);
}

test "SystemMetrics tracks sessions" {
    const allocator = testing.allocator;
    var metrics = try SystemMetrics.init(allocator);

    metrics.record_session_start();
    metrics.record_session_start();
    try testing.expectEqual(@as(u32, 2), metrics.active_sessions);

    metrics.record_session_end();
    try testing.expectEqual(@as(u32, 1), metrics.active_sessions);
}

test "SystemMetrics tracks commands" {
    const allocator = testing.allocator;
    var metrics = try SystemMetrics.init(allocator);

    metrics.record_command(true);
    metrics.record_command(true);
    metrics.record_command(false);

    try testing.expectEqual(@as(u64, 3), metrics.total_commands);
    try testing.expectEqual(@as(u64, 1), metrics.failed_commands);
}

test "SystemMetrics calculates success rate" {
    const allocator = testing.allocator;
    var metrics = try SystemMetrics.init(allocator);

    metrics.total_commands = 100;
    metrics.failed_commands = 10;

    const success_rate = metrics.command_success_rate();
    try testing.expect(success_rate > 89.0 and success_rate < 91.0);
}

test "PrometheusExporter generates valid Prometheus output" {
    const allocator = testing.allocator;
    var exporter = PrometheusExporter.init(allocator);

    var metrics = try SystemMetrics.init(allocator);
    metrics.active_connections = 10;
    metrics.active_sessions = 5;
    metrics.total_commands = 1000;

    const output = try exporter.export_system_metrics(metrics);
    defer allocator.free(output);

    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "tn3270_active_connections"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "HELP"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "TYPE"));
}

test "PrometheusExporter exports session metrics" {
    const allocator = testing.allocator;
    var exporter = PrometheusExporter.init(allocator);

    const session = SessionMetrics{
        .session_id = 42,
        .commands_processed = 500,
        .bytes_sent = 50000,
    };

    const output = try exporter.export_session_metrics(session);
    defer allocator.free(output);

    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "tn3270_session_commands"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "session_id"));
}

test "JSONExporter generates valid JSON" {
    const allocator = testing.allocator;
    var exporter = JSONExporter.init(allocator);

    var metrics = try SystemMetrics.init(allocator);
    metrics.active_connections = 10;
    metrics.active_sessions = 5;
    metrics.total_commands = 1000;
    metrics.failed_commands = 50;

    const output = try exporter.export_system_metrics(metrics);
    defer allocator.free(output);

    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "active_connections"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "10"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "{"));
}

test "JSONExporter exports session metrics" {
    const allocator = testing.allocator;
    var exporter = JSONExporter.init(allocator);

    const session = SessionMetrics{
        .session_id = 42,
        .commands_processed = 500,
        .bytes_sent = 50000,
        .bytes_received = 25000,
        .average_latency_ms = 25,
    };

    const output = try exporter.export_session_metrics(session);
    defer allocator.free(output);

    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "session_id"));
    try testing.expect(std.mem.containsAtLeast(u8, output, 1, "42"));
}
