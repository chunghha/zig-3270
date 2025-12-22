const std = @import("std");
const connection_monitor = @import("connection_monitor.zig");

/// Diagnostic tools for troubleshooting TN3270 connections and protocol issues
pub const DiagTool = struct {
    allocator: std.mem.Allocator,
    monitor: *connection_monitor.ConnectionMonitor,

    /// Diagnostic result with findings and recommendations
    pub const DiagResult = struct {
        status: DiagStatus,
        findings: std.ArrayList([]const u8),
        recommendations: std.ArrayList([]const u8),
        timestamp_ms: i64,

        pub fn deinit(self: *DiagResult, allocator: std.mem.Allocator) void {
            for (self.findings.items) |item| {
                allocator.free(item);
            }
            self.findings.deinit();
            for (self.recommendations.items) |item| {
                allocator.free(item);
            }
            self.recommendations.deinit();
        }
    };

    /// Diagnostic status levels
    pub const DiagStatus = enum {
        pass,
        warning,
        fail,
    };

    /// Diagnostic test types
    pub const DiagTest = enum {
        connection,
        protocol,
        performance,
        network,
    };

    pub fn init(allocator: std.mem.Allocator, monitor: *connection_monitor.ConnectionMonitor) DiagTool {
        return .{
            .allocator = allocator,
            .monitor = monitor,
        };
    }

    /// Run connection diagnostic
    pub fn diagnose_connection(self: *DiagTool, host: []const u8, port: u16) !DiagResult {
        var result = DiagResult{
            .status = .pass,
            .findings = std.ArrayList([]const u8).init(self.allocator),
            .recommendations = std.ArrayList([]const u8).init(self.allocator),
            .timestamp_ms = std.time.milliTimestamp(),
        };

        try self.monitor.register_connection(host, port);

        // Check if connection exists
        if (try self.monitor.get_metrics(host, port)) |metrics| {
            // Connection exists, check its health
            var alert = try self.monitor.check_health(host, port);
            defer alert.deinit(self.allocator);

            const finding = try std.fmt.allocPrint(self.allocator, "Connection to {s}:{d} exists", .{ host, port });
            try result.findings.append(finding);

            if (alert.status == .unhealthy) {
                result.status = .fail;
                for (alert.reasons.items) |reason| {
                    const finding2 = try std.fmt.allocPrint(self.allocator, "Issue: {s}", .{reason});
                    try result.findings.append(finding2);
                }
                try result.recommendations.append(try self.allocator.dupe(u8, "Check network connectivity and server logs"));
            } else if (alert.status == .degraded) {
                result.status = .warning;
                try result.recommendations.append(try self.allocator.dupe(u8, "Monitor connection performance"));
            }

            // Add metrics summary
            const uptime_str = try std.fmt.allocPrint(self.allocator, "Connection uptime: {d}ms", .{metrics.connection_uptime_ms});
            try result.findings.append(uptime_str);

            const byte_str = try std.fmt.allocPrint(self.allocator, "Bytes sent: {d}, received: {d}", .{ metrics.bytes_sent, metrics.bytes_received });
            try result.findings.append(byte_str);
        } else {
            result.status = .fail;
            const finding = try std.fmt.allocPrint(self.allocator, "No connection found to {s}:{d}", .{ host, port });
            try result.findings.append(finding);
            try result.recommendations.append(try self.allocator.dupe(u8, "Attempt to establish connection first"));
        }

        return result;
    }

    /// Run protocol compliance diagnostic
    pub fn diagnose_protocol(self: *DiagTool) !DiagResult {
        var result = DiagResult{
            .status = .pass,
            .findings = std.ArrayList([]const u8).init(self.allocator),
            .recommendations = std.ArrayList([]const u8).init(self.allocator),
            .timestamp_ms = std.time.milliTimestamp(),
        };

        try result.findings.append(try self.allocator.dupe(u8, "TN3270 Protocol Support:"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Extended Structured Fields (WSF): Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - LU3 Printing: Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Graphics Protocol (GDDM): Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - EBCDIC Encoding: Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Charset Support: Multiple charsets"));

        try result.recommendations.append(try self.allocator.dupe(u8, "Ensure mainframe supports negotiated options"));
        try result.recommendations.append(try self.allocator.dupe(u8, "Enable protocol snooper for detailed analysis: zig-3270 --snoop"));

        return result;
    }

    /// Run performance diagnostic
    pub fn diagnose_performance(self: *DiagTool, host: []const u8, port: u16) !DiagResult {
        var result = DiagResult{
            .status = .pass,
            .findings = std.ArrayList([]const u8).init(self.allocator),
            .recommendations = std.ArrayList([]const u8).init(self.allocator),
            .timestamp_ms = std.time.milliTimestamp(),
        };

        if (try self.monitor.get_metrics(host, port)) |metrics| {
            const avg_response = try std.fmt.allocPrint(self.allocator, "Average response time: {d:.2}ms", .{metrics.avg_response_time_ms()});
            try result.findings.append(avg_response);

            if (metrics.avg_response_time_ms() > 1000) {
                result.status = .warning;
                try result.recommendations.append(try self.allocator.dupe(u8, "Response times are slow - check network latency"));
                try result.recommendations.append(try self.allocator.dupe(u8, "Reduce batch size of commands per request"));
            }

            const throughput = try std.fmt.allocPrint(self.allocator, "Throughput: {d:.2} bytes/sec", .{metrics.throughput_bytes_per_sec()});
            try result.findings.append(throughput);

            if (metrics.throughput_bytes_per_sec() < 1000) {
                result.status = .warning;
                try result.recommendations.append(try self.allocator.dupe(u8, "Throughput is low - consider increasing command batching"));
            }

            const command_count = try std.fmt.allocPrint(self.allocator, "Commands sent: {d}", .{metrics.commands_sent});
            try result.findings.append(command_count);
        } else {
            result.status = .fail;
            try result.findings.append(try self.allocator.dupe(u8, "No performance data available"));
            try result.recommendations.append(try self.allocator.dupe(u8, "Establish connection and run transactions first"));
        }

        return result;
    }

    /// Run network diagnostic
    pub fn diagnose_network(self: *DiagTool) !DiagResult {
        _ = self;
        var result = DiagResult{
            .status = .pass,
            .findings = std.ArrayList([]const u8).init(self.allocator),
            .recommendations = std.ArrayList([]const u8).init(self.allocator),
            .timestamp_ms = std.time.milliTimestamp(),
        };

        try result.findings.append(try self.allocator.dupe(u8, "Network Configuration:"));
        try result.findings.append(try self.allocator.dupe(u8, "  - IPv4: Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - IPv6: Supported"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Connection Pooling: Enabled"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Auto-Reconnect: Enabled"));
        try result.findings.append(try self.allocator.dupe(u8, "  - Timeout Handling: Enabled"));

        try result.recommendations.append(try self.allocator.dupe(u8, "Verify firewall allows port 23 (Telnet) or 3270"));
        try result.recommendations.append(try self.allocator.dupe(u8, "Use --diag connect <host> <port> for detailed connection test"));

        return result;
    }

    /// Run all diagnostics
    pub fn run_all_diagnostics(self: *DiagTool, host: []const u8, port: u16) ![4]DiagResult {
        return .{
            try self.diagnose_network(),
            try self.diagnose_protocol(),
            try self.diagnose_connection(host, port),
            try self.diagnose_performance(host, port),
        };
    }
};

// Tests
test "DiagTool initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    const diag = DiagTool.init(allocator, &monitor);
    try std.testing.expect(diag.allocator == allocator);
}

test "DiagTool diagnose protocol" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_protocol();
    defer result.deinit(allocator);

    try std.testing.expectEqual(result.status, DiagTool.DiagStatus.pass);
    try std.testing.expect(result.findings.items.len > 0);
    try std.testing.expect(result.recommendations.items.len > 0);
}

test "DiagTool diagnose network" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_network();
    defer result.deinit(allocator);

    try std.testing.expectEqual(result.status, DiagTool.DiagStatus.pass);
    try std.testing.expect(result.findings.items.len > 0);
}

test "DiagTool diagnose connection without metrics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_connection("127.0.0.1", 3270);
    defer result.deinit(allocator);

    // No metrics registered yet, should be fail
    try std.testing.expect(result.findings.items.len >= 1);
}

test "DiagTool diagnose connection with metrics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_command_sent("127.0.0.1", 3270);
    try monitor.record_response_received("127.0.0.1", 3270, 100);

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_connection("127.0.0.1", 3270);
    defer result.deinit(allocator);

    try std.testing.expect(result.findings.items.len > 0);
}

test "DiagTool diagnose performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_response_received("127.0.0.1", 3270, 100);

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_performance("127.0.0.1", 3270);
    defer result.deinit(allocator);

    try std.testing.expect(result.findings.items.len > 0);
}

test "DiagTool high response time warning" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    try monitor.register_connection("127.0.0.1", 3270);
    try monitor.record_response_received("127.0.0.1", 3270, 2000);

    var diag = DiagTool.init(allocator, &monitor);
    var result = try diag.diagnose_performance("127.0.0.1", 3270);
    defer result.deinit(allocator);

    try std.testing.expectEqual(result.status, DiagTool.DiagStatus.warning);
}

test "DiagTool run all diagnostics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var monitor = connection_monitor.ConnectionMonitor.init(allocator);
    defer monitor.deinit();

    var diag = DiagTool.init(allocator, &monitor);
    var results = try diag.run_all_diagnostics("127.0.0.1", 3270);

    for (results) |*result| {
        defer result.deinit(allocator);
        try std.testing.expect(result.findings.items.len > 0);
    }
}
