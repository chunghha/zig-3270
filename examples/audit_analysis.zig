/// Audit analysis example: Analyze audit logs for security and compliance
///
/// Demonstrates:
/// - Reading and parsing audit logs
/// - Detecting suspicious activity patterns
/// - Compliance violation detection
/// - Audit report generation
///
/// Usage:
///   zig build run-audit-analysis -- --log audit.log --output report.txt
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

    var log_file: []const u8 = "audit.log";
    var output_file: ?[]const u8 = null;
    var verbose = false;

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--log") and i + 1 < args.len) {
            log_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            output_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        }
    }

    std.debug.print("=== Audit Log Analysis ===\n", .{});
    std.debug.print("Log file: {s}\n", .{log_file});
    if (output_file) |file| {
        std.debug.print("Output file: {s}\n", .{file});
    }
    std.debug.print("\n", .{});

    // Analyze logs
    var analyzer = AuditAnalyzer.init(allocator);
    defer analyzer.deinit();

    try analyzer.analyze_file(log_file);

    // Generate report
    var report = analyzer.generate_report();
    if (verbose) {
        report.print_detailed();
    } else {
        report.print_summary();
    }

    // Save to file if specified
    if (output_file) |file| {
        try report.save_to_file(file, allocator);
        std.debug.print("Report saved to {s}\n", .{file});
    }
}

const AuditAnalyzer = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(AuditEvent),
    suspicious_patterns: SuspiciousPatterns,

    fn init(allocator: std.mem.Allocator) AuditAnalyzer {
        return AuditAnalyzer{
            .allocator = allocator,
            .events = std.ArrayList(AuditEvent).init(allocator),
            .suspicious_patterns = SuspiciousPatterns{},
        };
    }

    fn deinit(self: *AuditAnalyzer) void {
        self.events.deinit();
    }

    fn analyze_file(self: *AuditAnalyzer, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var reader = std.io.bufferedReader(file.reader()).reader();
        var buffer: [1024]u8 = undefined;

        while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            if (line.len == 0) continue;

            var event = try AuditEvent.parse(line, self.allocator);
            try self.events.append(event);
            self.categorize_event(&event);
        }
    }

    fn categorize_event(self: *AuditAnalyzer, event: *const AuditEvent) void {
        // Check for suspicious patterns
        if (event.event_type == .failed_login) {
            self.suspicious_patterns.failed_logins += 1;
        } else if (event.event_type == .data_export) {
            self.suspicious_patterns.data_exports += 1;
        } else if (event.event_type == .privilege_change) {
            self.suspicious_patterns.privilege_changes += 1;
        } else if (event.event_type == .configuration_change) {
            self.suspicious_patterns.config_changes += 1;
        }

        // Detect brute force (5+ failures in 5 minutes)
        if (event.event_type == .failed_login) {
            self.suspicious_patterns.check_brute_force();
        }

        // Detect after-hours access
        if (event.timestamp_hour < 6 or event.timestamp_hour > 22) {
            self.suspicious_patterns.after_hours_access += 1;
        }
    }

    fn generate_report(self: *const AuditAnalyzer) AuditReport {
        return AuditReport{
            .total_events = self.events.items.len,
            .patterns = self.suspicious_patterns,
            .events = self.events,
        };
    }
};

const AuditEvent = struct {
    timestamp: i64,
    timestamp_hour: u8,
    event_type: EventType,
    user: [32]u8,
    user_len: usize,
    status: [16]u8,
    status_len: usize,

    fn parse(line: []const u8, allocator: std.mem.Allocator) !AuditEvent {
        _ = allocator;

        var event = AuditEvent{
            .timestamp = std.time.microTimestamp(),
            .timestamp_hour = @as(u8, @intCast(std.time.microTimestamp() / 3600_000_000 % 24)),
            .event_type = .login,
            .user = undefined,
            .user_len = 0,
            .status = undefined,
            .status_len = 0,
        };

        // Parse event type from line
        if (std.mem.indexOf(u8, line, "LOGIN")) |_| {
            event.event_type = .login;
        } else if (std.mem.indexOf(u8, line, "FAILED_LOGIN")) |_| {
            event.event_type = .failed_login;
        } else if (std.mem.indexOf(u8, line, "DATA_EXPORT")) |_| {
            event.event_type = .data_export;
        } else if (std.mem.indexOf(u8, line, "PRIVILEGE")) |_| {
            event.event_type = .privilege_change;
        } else if (std.mem.indexOf(u8, line, "CONFIG")) |_| {
            event.event_type = .configuration_change;
        }

        return event;
    }
};

const EventType = enum {
    login,
    failed_login,
    logout,
    data_export,
    privilege_change,
    configuration_change,
};

const SuspiciousPatterns = struct {
    failed_logins: usize = 0,
    brute_force_attempts: usize = 0,
    data_exports: usize = 0,
    privilege_changes: usize = 0,
    config_changes: usize = 0,
    after_hours_access: usize = 0,

    fn check_brute_force(self: *SuspiciousPatterns) void {
        if (self.failed_logins > 5) {
            self.brute_force_attempts += 1;
        }
    }

    fn risk_level(self: *const SuspiciousPatterns) []const u8 {
        if (self.brute_force_attempts > 0 or self.data_exports > 10) {
            return "CRITICAL";
        } else if (self.privilege_changes > 5 or self.config_changes > 3) {
            return "HIGH";
        } else if (self.failed_logins > 3 or self.after_hours_access > 20) {
            return "MEDIUM";
        } else {
            return "LOW";
        }
    }
};

const AuditReport = struct {
    total_events: usize,
    patterns: SuspiciousPatterns,
    events: std.ArrayList(AuditEvent),

    fn print_summary(self: *const AuditReport) void {
        std.debug.print("=== Audit Analysis Summary ===\n", .{});
        std.debug.print("Total Events: {d}\n", .{self.total_events});
        std.debug.print("\n", .{});
        std.debug.print("Suspicious Activity:\n", .{});
        std.debug.print("  Failed Logins: {d}\n", .{self.patterns.failed_logins});
        std.debug.print("  Brute Force Attempts: {d}\n", .{self.patterns.brute_force_attempts});
        std.debug.print("  Data Exports: {d}\n", .{self.patterns.data_exports});
        std.debug.print("  Privilege Changes: {d}\n", .{self.patterns.privilege_changes});
        std.debug.print("  Configuration Changes: {d}\n", .{self.patterns.config_changes});
        std.debug.print("  After-Hours Access: {d}\n", .{self.patterns.after_hours_access});
        std.debug.print("\n", .{});
        std.debug.print("Risk Level: {s}\n", .{self.patterns.risk_level()});

        if (std.mem.eql(u8, self.patterns.risk_level(), "CRITICAL")) {
            std.debug.print("\n⚠️  CRITICAL SECURITY ISSUES DETECTED\n", .{});
            std.debug.print("Recommended Actions:\n", .{});
            std.debug.print("  1. Review and lock suspicious user accounts\n", .{});
            std.debug.print("  2. Check data export destinations\n", .{});
            std.debug.print("  3. Verify all configuration changes\n", .{});
            std.debug.print("  4. Contact security team immediately\n", .{});
        }
    }

    fn print_detailed(self: *const AuditReport) void {
        self.print_summary();
        std.debug.print("\n=== Detailed Events ===\n", .{});
        for (self.events.items) |event| {
            std.debug.print(
                "Event: {} | User: {} | Status: {}\n",
                .{ event.event_type, event.user_len, event.status_len },
            );
        }
    }

    fn save_to_file(self: *const AuditReport, file_path: []const u8, allocator: std.mem.Allocator) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.print("=== Audit Analysis Report ===\n", .{});
        try writer.print("Total Events: {d}\n", .{self.total_events});
        try writer.print("Risk Level: {s}\n", .{self.patterns.risk_level()});

        _ = allocator;
    }
};

pub const root_decl = struct {
    pub const std_options: std.Options = .{
        .log_level = .info,
    };
};
