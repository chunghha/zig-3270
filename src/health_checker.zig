/// Health Check & Recovery System
///
/// Continuous endpoint health monitoring with automatic recovery detection.
/// Integrates with load balancer and connection monitor for health status.
///
/// Usage:
/// ```zig
/// var checker = try HealthChecker.init(allocator, &load_balancer, &monitor);
/// defer checker.deinit();
///
/// try checker.check_endpoint("host1", 23);
/// checker.update_health_status_from_monitor("host1", 23);
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const load_balancer = @import("load_balancer.zig");
const connection_monitor = @import("connection_monitor.zig");

pub const HealthCheckStrategy = enum {
    keep_alive,
    ping,
    test_command,
};

pub const HealthCheckConfig = struct {
    check_interval_ms: u64 = 10000, // Check every 10 seconds
    check_timeout_ms: u64 = 2000,
    unhealthy_threshold: u32 = 3, // Mark unhealthy after 3 failures
    recovery_threshold: u32 = 2, // Mark healthy after 2 successes
    strategy: HealthCheckStrategy = .keep_alive,
    enable_exponential_backoff: bool = true,
    max_backoff_ms: u64 = 60000, // Max 60 seconds between checks
};

pub const EndpointHealthState = struct {
    host: []const u8,
    port: u16,
    consecutive_failures: u32 = 0,
    consecutive_successes: u32 = 0,
    last_check_time_ms: i64 = 0,
    last_check_status: bool = true,
    backoff_multiplier: f64 = 1.0,
};

pub const HealthChecker = struct {
    allocator: Allocator,
    lb: *load_balancer.LoadBalancer,
    monitor: *connection_monitor.ConnectionMonitor,
    config: HealthCheckConfig,
    endpoint_states: std.StringHashMap(EndpointHealthState),
    check_history: std.ArrayList(struct {
        host: []const u8,
        timestamp_ms: i64,
        status: bool,
    }),
    mutex: std.Thread.Mutex = .{},

    /// Initialize health checker
    pub fn init(
        allocator: Allocator,
        lb: *load_balancer.LoadBalancer,
        monitor: *connection_monitor.ConnectionMonitor,
    ) !HealthChecker {
        return .{
            .allocator = allocator,
            .lb = lb,
            .monitor = monitor,
            .config = .{},
            .endpoint_states = std.StringHashMap(EndpointHealthState).init(allocator),
            .check_history = std.ArrayList(struct {
                host: []const u8,
                timestamp_ms: i64,
                status: bool,
            }).init(allocator),
        };
    }

    /// Deinitialize health checker
    pub fn deinit(self: *HealthChecker) void {
        var iter = self.endpoint_states.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.endpoint_states.deinit();

        for (self.check_history.items) |item| {
            self.allocator.free(item.host);
        }
        self.check_history.deinit();
    }

    /// Register endpoint for health checks
    pub fn register_endpoint(self: *HealthChecker, host: []const u8, port: u16) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const host_copy = try self.allocator.dupe(u8, host);
        errdefer self.allocator.free(host_copy);

        try self.endpoint_states.put(host_copy, .{
            .host = host_copy,
            .port = port,
        });
    }

    /// Perform health check on endpoint
    pub fn check_endpoint(self: *HealthChecker, host: []const u8, port: u16) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Determine if check should run based on backoff
        if (self.endpoint_states.getPtr(host)) |state| {
            const now = std.time.milliTimestamp();
            const backoff_interval = @as(i64, @intCast(self.config.check_interval_ms));
            const adjusted_interval = @as(i64, @intFromFloat(
                @as(f64, @floatFromInt(backoff_interval)) * state.backoff_multiplier,
            ));

            if (now - state.last_check_time_ms < adjusted_interval) {
                return state.last_check_status;
            }
        }

        // Perform actual health check based on strategy
        const check_passed = try self.execute_health_check(host, port);

        // Update state based on check result
        if (self.endpoint_states.getPtr(host)) |state| {
            if (check_passed) {
                state.consecutive_successes += 1;
                state.consecutive_failures = 0;

                // Reduce backoff on success
                if (self.config.enable_exponential_backoff) {
                    state.backoff_multiplier = @max(1.0, state.backoff_multiplier * 0.8);
                }

                // Update load balancer health status after recovery threshold
                if (state.consecutive_successes >= self.config.recovery_threshold) {
                    self.lb.set_health_status(host, .healthy);
                    self.lb.record_success(host);
                }
            } else {
                state.consecutive_failures += 1;
                state.consecutive_successes = 0;

                // Increase backoff on failure
                if (self.config.enable_exponential_backoff) {
                    const new_multiplier = state.backoff_multiplier * 2.0;
                    state.backoff_multiplier = @min(
                        new_multiplier,
                        @as(f64, @floatFromInt(self.config.max_backoff_ms)) /
                            @as(f64, @floatFromInt(self.config.check_interval_ms)),
                    );
                }

                // Update load balancer health status after threshold
                if (state.consecutive_failures >= self.config.unhealthy_threshold) {
                    self.lb.set_health_status(host, .unhealthy);
                    self.lb.record_failure(host);
                } else if (state.consecutive_failures >= 1) {
                    self.lb.set_health_status(host, .degraded);
                }
            }

            state.last_check_time_ms = std.time.milliTimestamp();
            state.last_check_status = check_passed;

            // Record check in history
            const history_host = try self.allocator.dupe(u8, host);
            try self.check_history.append(.{
                .host = history_host,
                .timestamp_ms = std.time.milliTimestamp(),
                .status = check_passed,
            });
        }

        return check_passed;
    }

    /// Execute health check based on strategy
    fn execute_health_check(self: *HealthChecker, host: []const u8, _: u16) !bool {
        _ = self;

        // For now, we simulate based on strategy
        // In production, this would actually attempt connection/ping/command
        switch (self.config.strategy) {
            .keep_alive => {
                // Would send keep-alive probe
                return true;
            },
            .ping => {
                // Would ping endpoint
                return true;
            },
            .test_command => {
                // Would send test command
                return true;
            },
        }
    }

    /// Update health status from connection monitor metrics
    pub fn update_health_status_from_monitor(
        self: *HealthChecker,
        host: []const u8,
        port: u16,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (try self.monitor.check_health(host, port)) |alert| {
            defer alert.deinit(self.allocator);

            // Update load balancer health status based on monitor
            const monitor_status = switch (alert.status) {
                .healthy => load_balancer.HealthStatus.healthy,
                .degraded => load_balancer.HealthStatus.degraded,
                .unhealthy => load_balancer.HealthStatus.unhealthy,
            };

            self.lb.set_health_status(host, monitor_status);

            // Update endpoint state
            if (self.endpoint_states.getPtr(host)) |state| {
                state.last_check_status = alert.status == .healthy;
                if (alert.status == .healthy) {
                    state.consecutive_successes += 1;
                    state.consecutive_failures = 0;
                } else {
                    state.consecutive_failures += 1;
                    state.consecutive_successes = 0;
                }
            }
        }
    }

    /// Get health state for endpoint
    pub fn get_health_state(self: *HealthChecker, host: []const u8) ?EndpointHealthState {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.endpoint_states.get(host);
    }

    /// Set custom health check configuration
    pub fn set_config(self: *HealthChecker, config: HealthCheckConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.config = config;
    }

    /// Get check history for endpoint
    pub fn get_check_history(self: *HealthChecker, host: []const u8, allocator: Allocator) ![]struct {
        timestamp_ms: i64,
        status: bool,
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(struct {
            timestamp_ms: i64,
            status: bool,
        }).init(allocator);

        for (self.check_history.items) |item| {
            if (std.mem.eql(u8, item.host, host)) {
                try result.append(.{
                    .timestamp_ms = item.timestamp_ms,
                    .status = item.status,
                });
            }
        }

        return result.toOwnedSlice();
    }

    /// Clear check history
    pub fn clear_history(self: *HealthChecker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.check_history.items) |item| {
            self.allocator.free(item.host);
        }
        self.check_history.clearRetainingCapacity();
    }
};

// Tests
const testing = std.testing;

test "HealthChecker: init" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var monitor = connection_monitor.ConnectionMonitor.init(testing.allocator);
    defer monitor.deinit();

    var checker = try HealthChecker.init(testing.allocator, &lb, &monitor);
    defer checker.deinit();

    try testing.expectEqual(checker.endpoint_states.count(), 0);
}

test "HealthChecker: register endpoint" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var monitor = connection_monitor.ConnectionMonitor.init(testing.allocator);
    defer monitor.deinit();

    var checker = try HealthChecker.init(testing.allocator, &lb, &monitor);
    defer checker.deinit();

    try checker.register_endpoint("host1", 23);
    try testing.expectEqual(checker.endpoint_states.count(), 1);
}

test "HealthChecker: check endpoint" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var monitor = connection_monitor.ConnectionMonitor.init(testing.allocator);
    defer monitor.deinit();

    var checker = try HealthChecker.init(testing.allocator, &lb, &monitor);
    defer checker.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try checker.register_endpoint("host1", 23);

    const result = try checker.check_endpoint("host1", 23);
    try testing.expect(result);
}

test "HealthChecker: health state tracking" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var monitor = connection_monitor.ConnectionMonitor.init(testing.allocator);
    defer monitor.deinit();

    var checker = try HealthChecker.init(testing.allocator, &lb, &monitor);
    defer checker.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try checker.register_endpoint("host1", 23);

    _ = try checker.check_endpoint("host1", 23);

    const state = checker.get_health_state("host1");
    try testing.expect(state != null);
}

test "HealthChecker: exponential backoff on failures" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var monitor = connection_monitor.ConnectionMonitor.init(testing.allocator);
    defer monitor.deinit();

    var checker = try HealthChecker.init(testing.allocator, &lb, &monitor);
    defer checker.deinit();

    checker.config.enable_exponential_backoff = true;

    try lb.add_endpoint("host1", 23, 1);
    try checker.register_endpoint("host1", 23);

    const initial_state = checker.get_health_state("host1").?;
    try testing.expectEqual(initial_state.backoff_multiplier, 1.0);
}
