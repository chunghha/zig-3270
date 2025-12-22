/// Session monitor example: Real-time monitoring of TN3270 sessions
///
/// Demonstrates:
/// - Session pool management
/// - Real-time metrics collection
/// - Health status monitoring
/// - Connection tracking
///
/// Usage:
///   zig build run-session-monitor -- --host mainframe.example.com --port 23 --sessions 5
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
    var num_sessions: usize = 5;
    var refresh_interval_ms: u64 = 1000;

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port = try std.fmt.parseUnsigned(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--sessions") and i + 1 < args.len) {
            num_sessions = try std.fmt.parseUnsigned(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--interval") and i + 1 < args.len) {
            refresh_interval_ms = try std.fmt.parseUnsigned(u64, args[i + 1], 10);
            i += 1;
        }
    }

    std.debug.print("=== Session Monitor ===\n", .{});
    std.debug.print("Monitoring {d} sessions to {s}:{d}\n", .{ num_sessions, host, port });
    std.debug.print("Refresh interval: {d}ms\n", .{refresh_interval_ms});
    std.debug.print("Press Ctrl+C to exit\n\n", .{});

    // Create session monitors
    var sessions = try allocator.alloc(SessionMonitor, num_sessions);
    defer allocator.free(sessions);

    for (sessions) |*session| {
        session.* = SessionMonitor{
            .host = host,
            .port = port,
            .session_id = session - sessions.ptr,
        };
    }

    // Main monitoring loop
    var running = true;
    while (running) {
        // Clear screen and print header
        std.debug.print("\x1B[2J\x1B[H", .{}); // ANSI clear screen
        print_header();

        // Update and display each session
        var total_commands: u64 = 0;
        var total_errors: u64 = 0;
        var healthy_sessions: usize = 0;

        for (sessions) |*session| {
            session.update();
            session.print();

            total_commands += session.commands_processed;
            total_errors += session.errors;
            if (session.is_healthy()) healthy_sessions += 1;
        }

        // Print summary
        print_footer(num_sessions, healthy_sessions, total_commands, total_errors);

        // Sleep before refresh
        std.time.sleep(refresh_interval_ms * 1_000_000);
    }
}

const SessionMonitor = struct {
    host: []const u8,
    port: u16,
    session_id: usize,

    // Metrics
    connected: bool = false,
    latency_us: u64 = 0,
    commands_processed: u64 = 0,
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    errors: u64 = 0,
    last_activity: i64 = 0,

    fn update(self: *SessionMonitor) void {
        // Simulate session update
        // In real scenario, this would query actual session stats

        // Random latency simulation (50-200µs)
        const random_delay = 50 + (self.session_id * 37 % 150);
        self.latency_us = random_delay;

        // Simulate command processing
        self.commands_processed += 10 + (self.session_id * 7 % 20);

        // Simulate data transfer
        self.bytes_sent += 100 + (self.session_id * 13 % 500);
        self.bytes_received += 500 + (self.session_id * 17 % 2000);

        // 1% error rate simulation
        if (self.commands_processed % 100 == 0) {
            self.errors += 1;
        }

        // Update last activity
        self.last_activity = std.time.microTimestamp();

        // Connection status
        self.connected = self.errors < self.commands_processed / 50;
    }

    fn is_healthy(self: *const SessionMonitor) bool {
        return self.connected and self.errors < self.commands_processed / 50;
    }

    fn print(self: *const SessionMonitor) void {
        const status = if (self.connected) "✓ Connected" else "✗ Disconnected";
        const health = if (self.is_healthy()) "Healthy" else "Degraded";
        const error_rate = if (self.commands_processed > 0)
            100.0 * @as(f64, @floatFromInt(self.errors)) / @as(f64, @floatFromInt(self.commands_processed))
        else
            0.0;

        std.debug.print(
            "Session {d}: {s} | {s} | Latency: {d}µs | Cmds: {d} | Errors: {d} ({d:.2}%) | TX: {d} B | RX: {d} B\n",
            .{
                self.session_id,
                status,
                health,
                self.latency_us,
                self.commands_processed,
                self.errors,
                error_rate,
                self.bytes_sent,
                self.bytes_received,
            },
        );
    }
};

fn print_header() void {
    std.debug.print("┌─ TN3270 Session Monitor ──────────────────────────────────────────┐\n", .{});
    std.debug.print("│ Session │ Status      │ Health    │ Latency │ Commands │ Errors   │\n", .{});
    std.debug.print("├─────────┼─────────────┼───────────┼─────────┼──────────┼──────────┤\n", .{});
}

fn print_footer(total_sessions: usize, healthy: usize, commands: u64, errors: u64) void {
    const error_rate = if (commands > 0)
        100.0 * @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(commands))
    else
        0.0;

    std.debug.print("├─────────────────────────────────────────────────────────────────────┤\n", .{});
    std.debug.print("│ Total Sessions: {d}  │ Healthy: {d}  │ Commands: {d}  │ Error Rate: {d:.2}% │\n", .{
        total_sessions,
        healthy,
        commands,
        error_rate,
    });
    std.debug.print("└──────────────────────────────────────────────────────────────────────┘\n", .{});
}

pub const root_decl = struct {
    pub const std_options: std.Options = .{
        .log_level = .info,
    };
};
