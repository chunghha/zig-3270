/// Failover Management
///
/// Automatic endpoint failure detection and session migration.
/// Handles failover events, automatic recovery, and fallback chains.
///
/// Usage:
/// ```zig
/// var failover = try Failover.init(allocator, &load_balancer, &session_pool);
/// defer failover.deinit();
///
/// try failover.detect_failure("host1");
/// const target = try failover.find_replacement_endpoint("host1");
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const load_balancer = @import("load_balancer.zig");
const session_pool = @import("session_pool.zig");

pub const FailoverStatus = enum {
    detecting,
    migrating,
    completed,
    partial_failure,
    all_failed,
};

pub const FailoverEvent = struct {
    failed_endpoint_host: []const u8,
    failed_endpoint_port: u16,
    affected_sessions: std.ArrayList([]const u8),
    target_endpoint: ?load_balancer.Endpoint = null,
    status: FailoverStatus,
    timestamp_ms: i64,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: *FailoverEvent, allocator: Allocator) void {
        for (self.affected_sessions.items) |session_id| {
            allocator.free(session_id);
        }
        self.affected_sessions.deinit();
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

pub const FailoverConfig = struct {
    failover_timeout_ms: u64 = 5000,
    max_retries: u32 = 3,
    retry_delay_ms: u64 = 500,
    enable_auto_recovery: bool = true,
    fallback_chain_size: u32 = 3,
};

pub const Failover = struct {
    allocator: Allocator,
    lb: *load_balancer.LoadBalancer,
    pool: *session_pool.SessionPool,
    config: FailoverConfig,
    failed_endpoints: std.StringHashMap(u32), // endpoint host -> failure count
    failover_events: std.ArrayList(FailoverEvent),
    mutex: std.Thread.Mutex = .{},

    /// Initialize failover manager
    pub fn init(
        allocator: Allocator,
        lb: *load_balancer.LoadBalancer,
        pool: *session_pool.SessionPool,
    ) !Failover {
        return .{
            .allocator = allocator,
            .lb = lb,
            .pool = pool,
            .config = .{},
            .failed_endpoints = std.StringHashMap(u32).init(allocator),
            .failover_events = std.ArrayList(FailoverEvent).init(allocator),
        };
    }

    /// Deinitialize failover manager
    pub fn deinit(self: *Failover) void {
        var iter = self.failed_endpoints.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.failed_endpoints.deinit();

        for (self.failover_events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.failover_events.deinit();
    }

    /// Detect endpoint failure
    pub fn detect_failure(
        self: *Failover,
        failed_host: []const u8,
        failed_port: u16,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update failure count
        const host_copy = try self.allocator.dupe(u8, failed_host);
        const failure_count = (self.failed_endpoints.get(host_copy) orelse 0) + 1;
        try self.failed_endpoints.put(host_copy, failure_count);

        // Mark endpoint as degraded/unhealthy
        self.lb.set_health_status(
            failed_host,
            if (failure_count > 1) .unhealthy else .degraded,
        );
        self.lb.record_failure(failed_host);

        // Create failover event
        var event = FailoverEvent{
            .failed_endpoint_host = try self.allocator.dupe(u8, failed_host),
            .failed_endpoint_port = failed_port,
            .affected_sessions = std.ArrayList([]const u8).init(self.allocator),
            .status = .detecting,
            .timestamp_ms = std.time.milliTimestamp(),
        };

        try self.failover_events.append(event);
    }

    /// Find replacement endpoint for failed one
    pub fn find_replacement_endpoint(
        self: *Failover,
        failed_host: []const u8,
    ) !?*load_balancer.Endpoint {
        self.mutex.lock();
        defer self.mutex.unlock();

        var healthy_endpoints = std.ArrayList(*load_balancer.Endpoint).init(self.allocator);
        defer healthy_endpoints.deinit();

        // Collect healthy endpoints excluding the failed one
        for (self.lb.endpoints.items) |*endpoint| {
            if (!std.mem.eql(u8, endpoint.host, failed_host) and
                endpoint.health_status == .healthy)
            {
                try healthy_endpoints.append(endpoint);
            }
        }

        if (healthy_endpoints.items.len == 0) {
            return null;
        }

        // Return endpoint with least connections
        var best_endpoint = healthy_endpoints.items[0];
        for (healthy_endpoints.items[1..]) |endpoint| {
            if (endpoint.active_sessions < best_endpoint.active_sessions) {
                best_endpoint = endpoint;
            }
        }

        return best_endpoint;
    }

    /// Get fallback chain for failed endpoint
    pub fn get_fallback_chain(
        self: *Failover,
        failed_host: []const u8,
    ) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var fallback_hosts = std.ArrayList([]const u8).init(self.allocator);
        var added_count: u32 = 0;

        // First: healthy endpoints with lowest connections
        var candidates = std.ArrayList(struct {
            host: []const u8,
            connections: u32,
        }).init(self.allocator);
        defer candidates.deinit();

        for (self.lb.endpoints.items) |endpoint| {
            if (!std.mem.eql(u8, endpoint.host, failed_host) and
                endpoint.health_status == .healthy)
            {
                try candidates.append(.{
                    .host = endpoint.host,
                    .connections = endpoint.active_sessions,
                });
            }
        }

        // Sort by connections (ascending)
        std.mem.sort(
            struct { host: []const u8, connections: u32 },
            candidates.items,
            {},
            struct {
                fn compare(_: void, a: struct { host: []const u8, connections: u32 }, b: struct { host: []const u8, connections: u32 }) bool {
                    return a.connections < b.connections;
                }
            }.compare,
        );

        // Add top candidates
        for (candidates.items) |candidate| {
            if (added_count >= self.config.fallback_chain_size) {
                break;
            }
            try fallback_hosts.append(candidate.host);
            added_count += 1;
        }

        return fallback_hosts.toOwnedSlice();
    }

    /// Migrate sessions from failed endpoint to target
    pub fn migrate_sessions(
        self: *Failover,
        failed_host: []const u8,
        target_endpoint: *load_balancer.Endpoint,
    ) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var migrated_count: u32 = 0;
        var all_sessions = try self.pool.all_sessions(self.allocator);
        defer self.allocator.free(all_sessions);

        for (all_sessions) |session_id| {
            if (self.pool.get_session(session_id)) |sess| {
                // Check if session belongs to failed endpoint
                if (std.mem.eql(u8, sess.metadata.host, failed_host)) {
                    // Update session metadata to target endpoint
                    if (self.pool.sessions.getPtr(session_id)) |mutable_sess| {
                        mutable_sess.metadata.host = target_endpoint.host;
                        mutable_sess.metadata.port = target_endpoint.port;
                        migrated_count += 1;
                    }
                }
            }
        }

        return migrated_count;
    }

    /// Handle endpoint recovery
    pub fn handle_recovery(self: *Failover, recovered_host: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Reset failure count
        if (self.failed_endpoints.getPtr(recovered_host)) |count| {
            count.* = 0;
        }

        // Mark endpoint as healthy
        self.lb.set_health_status(recovered_host, .healthy);
        self.lb.record_success(recovered_host);
    }

    /// Execute complete failover procedure
    pub fn execute_failover(
        self: *Failover,
        failed_host: []const u8,
        failed_port: u16,
    ) !FailoverStatus {
        try self.detect_failure(failed_host, failed_port);

        const target = try self.find_replacement_endpoint(failed_host);
        if (target == null) {
            return .all_failed;
        }

        const migrated = try self.migrate_sessions(failed_host, target.?);

        if (migrated > 0) {
            return .completed;
        } else {
            return .partial_failure;
        }
    }

    /// Get failover events
    pub fn get_events(self: *Failover, allocator: Allocator) ![]FailoverEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(FailoverEvent).init(allocator);
        for (self.failover_events.items) |event| {
            try result.append(event);
        }
        return result.toOwnedSlice();
    }

    /// Clear failover events
    pub fn clear_events(self: *Failover) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.failover_events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.failover_events.clearRetainingCapacity();
    }

    /// Get failure count for endpoint
    pub fn get_failure_count(self: *Failover, host: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.failed_endpoints.get(host) orelse 0;
    }
};

// Tests
const testing = std.testing;

test "Failover: init" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try testing.expectEqual(failover.failover_events.items.len, 0);
}

test "Failover: detect failure" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try lb.add_endpoint("host1", 23, 1);
    lb.set_health_status("host1", .healthy);

    try failover.detect_failure("host1", 23);

    try testing.expectEqual(failover.failover_events.items.len, 1);
    try testing.expectEqual(failover.failover_events.items[0].status, .detecting);
}

test "Failover: find replacement endpoint" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    lb.set_health_status("host1", .healthy);
    lb.set_health_status("host2", .healthy);

    const target = try failover.find_replacement_endpoint("host1");
    try testing.expect(target != null);
    try testing.expectEqualStrings(target.?.host, "host2");
}

test "Failover: no replacement available" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    lb.set_health_status("host1", .healthy);
    lb.set_health_status("host2", .unhealthy);

    const target = try failover.find_replacement_endpoint("host1");
    try testing.expect(target == null);
}

test "Failover: execute failover" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    lb.set_health_status("host1", .healthy);
    lb.set_health_status("host2", .healthy);

    const result = try failover.execute_failover("host1", 23);
    try testing.expect(result == .completed or result == .partial_failure);
}

test "Failover: failure count tracking" {
    var lb = try load_balancer.LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var failover = try Failover.init(testing.allocator, &lb, &pool);
    defer failover.deinit();

    try lb.add_endpoint("host1", 23, 1);

    try failover.detect_failure("host1", 23);
    try failover.detect_failure("host1", 23);

    const count = failover.get_failure_count("host1");
    try testing.expect(count > 0);
}
