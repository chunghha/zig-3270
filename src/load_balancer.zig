/// Load Balancer
///
/// Distributes sessions across multiple endpoints using various strategies.
/// Supports round-robin, weighted, least-connections, least-response-time, and random.
///
/// Usage:
/// ```zig
/// var lb = try LoadBalancer.init(allocator);
/// defer lb.deinit();
///
/// try lb.add_endpoint("host1", 23, 1);
/// try lb.add_endpoint("host2", 23, 2);
///
/// const endpoint = try lb.select_endpoint(.weighted_round_robin);
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const connection_monitor = @import("connection_monitor.zig");

pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
};

pub const Endpoint = struct {
    host: []const u8,
    port: u16,
    weight: u32 = 1,
    health_status: HealthStatus = .healthy,
    active_sessions: u32 = 0,
    failed_attempts: u32 = 0,
    last_response_time_ms: u32 = 0,
};

pub const Strategy = enum {
    round_robin,
    weighted_round_robin,
    least_connections,
    least_response_time,
    random,
};

pub const LoadBalancerStats = struct {
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    active_sessions: u32 = 0,
    strategy: Strategy,
    request_distribution: std.StringHashMap(u64),
};

pub const LoadBalancer = struct {
    endpoints: std.ArrayList(Endpoint),
    allocator: Allocator,
    strategy: Strategy,
    stats: LoadBalancerStats,
    round_robin_index: u32 = 0,
    mutex: std.Thread.Mutex = .{},
    random_gen: std.Random.DefaultPrng,

    /// Initialize load balancer with default round-robin strategy
    pub fn init(allocator: Allocator) !LoadBalancer {
        var lb = LoadBalancer{
            .endpoints = std.ArrayList(Endpoint).init(allocator),
            .allocator = allocator,
            .strategy = .round_robin,
            .stats = .{
                .strategy = .round_robin,
                .request_distribution = std.StringHashMap(u64).init(allocator),
            },
            .random_gen = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp())),
        };
        return lb;
    }

    /// Deinitialize load balancer
    pub fn deinit(self: *LoadBalancer) void {
        for (self.endpoints.items) |endpoint| {
            self.allocator.free(endpoint.host);
        }
        self.endpoints.deinit();

        var iter = self.stats.request_distribution.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.stats.request_distribution.deinit();
    }

    /// Add endpoint to load balancer
    pub fn add_endpoint(self: *LoadBalancer, host: []const u8, port: u16, weight: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const host_copy = try self.allocator.dupe(u8, host);
        errdefer self.allocator.free(host_copy);

        try self.endpoints.append(.{
            .host = host_copy,
            .port = port,
            .weight = weight,
        });

        // Initialize request distribution tracking
        try self.stats.request_distribution.put(host_copy, 0);
    }

    /// Remove endpoint from load balancer
    pub fn remove_endpoint(self: *LoadBalancer, host: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items, 0..) |endpoint, i| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                const removed = self.endpoints.swapRemove(i);
                self.allocator.free(removed.host);
                _ = self.stats.request_distribution.remove(host);
                return true;
            }
        }
        return false;
    }

    /// Select endpoint based on current strategy
    pub fn select_endpoint(self: *LoadBalancer, strategy: Strategy) !*Endpoint {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.endpoints.items.len == 0) {
            return error.NoEndpointsAvailable;
        }

        // Filter healthy endpoints
        var healthy_indices = std.ArrayList(usize).init(self.allocator);
        defer healthy_indices.deinit();

        for (self.endpoints.items, 0..) |endpoint, i| {
            if (endpoint.health_status == .healthy) {
                try healthy_indices.append(i);
            }
        }

        // Fallback to degraded if no healthy endpoints
        if (healthy_indices.items.len == 0) {
            for (self.endpoints.items, 0..) |endpoint, i| {
                if (endpoint.health_status == .degraded) {
                    try healthy_indices.append(i);
                }
            }
        }

        if (healthy_indices.items.len == 0) {
            return error.NoHealthyEndpointsAvailable;
        }

        const index = switch (strategy) {
            .round_robin => try self.select_round_robin(healthy_indices.items),
            .weighted_round_robin => try self.select_weighted_round_robin(healthy_indices.items),
            .least_connections => try self.select_least_connections(healthy_indices.items),
            .least_response_time => try self.select_least_response_time(healthy_indices.items),
            .random => try self.select_random(healthy_indices.items),
        };

        const endpoint = &self.endpoints.items[index];
        endpoint.active_sessions += 1;
        self.stats.total_requests += 1;
        self.stats.successful_requests += 1;
        self.stats.active_sessions = self.count_active_sessions();

        // Update distribution stats
        if (self.stats.request_distribution.getPtr(endpoint.host)) |count| {
            count.* += 1;
        }

        return endpoint;
    }

    /// Record endpoint failure
    pub fn record_failure(self: *LoadBalancer, host: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                endpoint.failed_attempts += 1;
                self.stats.failed_requests += 1;
                break;
            }
        }
    }

    /// Record endpoint success
    pub fn record_success(self: *LoadBalancer, host: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                endpoint.failed_attempts = 0;
                break;
            }
        }
    }

    /// Update endpoint health status
    pub fn set_health_status(self: *LoadBalancer, host: []const u8, status: HealthStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                endpoint.health_status = status;
                break;
            }
        }
    }

    /// Update endpoint response time
    pub fn record_response_time(self: *LoadBalancer, host: []const u8, response_time_ms: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                endpoint.last_response_time_ms = response_time_ms;
                break;
            }
        }
    }

    /// Decrement active sessions for endpoint
    pub fn decrement_active_sessions(self: *LoadBalancer, host: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                if (endpoint.active_sessions > 0) {
                    endpoint.active_sessions -= 1;
                }
                self.stats.active_sessions = self.count_active_sessions();
                break;
            }
        }
    }

    /// Set load balancer strategy
    pub fn set_strategy(self: *LoadBalancer, strategy: Strategy) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.strategy = strategy;
        self.stats.strategy = strategy;
    }

    /// Get endpoint by host
    pub fn get_endpoint(self: *LoadBalancer, host: []const u8) ?*Endpoint {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.endpoints.items) |*endpoint| {
            if (std.mem.eql(u8, endpoint.host, host)) {
                return endpoint;
            }
        }
        return null;
    }

    /// Count total active sessions across all endpoints
    fn count_active_sessions(self: *LoadBalancer) u32 {
        var count: u32 = 0;
        for (self.endpoints.items) |endpoint| {
            count += endpoint.active_sessions;
        }
        return count;
    }

    /// Get statistics snapshot
    pub fn get_stats(self: *LoadBalancer) LoadBalancerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = self.stats;
        stats.active_sessions = self.count_active_sessions();
        return stats;
    }

    /// Round-robin selection
    fn select_round_robin(self: *LoadBalancer, healthy_indices: []usize) !usize {
        if (healthy_indices.len == 0) return error.NoHealthyEndpointsAvailable;

        const index = self.round_robin_index % healthy_indices.len;
        self.round_robin_index += 1;
        return healthy_indices[index];
    }

    /// Weighted round-robin selection
    fn select_weighted_round_robin(self: *LoadBalancer, healthy_indices: []usize) !usize {
        if (healthy_indices.len == 0) return error.NoHealthyEndpointsAvailable;

        var total_weight: u32 = 0;
        for (healthy_indices) |idx| {
            total_weight += self.endpoints.items[idx].weight;
        }

        if (total_weight == 0) return healthy_indices[0];

        var weighted_choice = (self.round_robin_index % total_weight);
        self.round_robin_index += 1;

        var cumulative: u32 = 0;
        for (healthy_indices) |idx| {
            cumulative += self.endpoints.items[idx].weight;
            if (weighted_choice < cumulative) {
                return idx;
            }
        }

        return healthy_indices[0];
    }

    /// Least connections selection
    fn select_least_connections(self: *LoadBalancer, healthy_indices: []usize) !usize {
        if (healthy_indices.len == 0) return error.NoHealthyEndpointsAvailable;

        var min_connections = self.endpoints.items[healthy_indices[0]].active_sessions;
        var selected_idx: usize = 0;

        for (healthy_indices, 0..) |idx, i| {
            if (self.endpoints.items[idx].active_sessions < min_connections) {
                min_connections = self.endpoints.items[idx].active_sessions;
                selected_idx = i;
            }
        }

        return healthy_indices[selected_idx];
    }

    /// Least response time selection
    fn select_least_response_time(self: *LoadBalancer, healthy_indices: []usize) !usize {
        if (healthy_indices.len == 0) return error.NoHealthyEndpointsAvailable;

        var min_response_time = self.endpoints.items[healthy_indices[0]].last_response_time_ms;
        var selected_idx: usize = 0;

        for (healthy_indices, 0..) |idx, i| {
            if (self.endpoints.items[idx].last_response_time_ms < min_response_time) {
                min_response_time = self.endpoints.items[idx].last_response_time_ms;
                selected_idx = i;
            }
        }

        return healthy_indices[selected_idx];
    }

    /// Random selection
    fn select_random(self: *LoadBalancer, healthy_indices: []usize) !usize {
        if (healthy_indices.len == 0) return error.NoHealthyEndpointsAvailable;

        const random_idx = self.random_gen.random().uintLessThan(usize, healthy_indices.len);
        return healthy_indices[random_idx];
    }
};

// Tests
const testing = std.testing;

test "LoadBalancer: init" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try testing.expectEqual(lb.endpoints.items.len, 0);
    try testing.expectEqual(lb.strategy, .round_robin);
}

test "LoadBalancer: add endpoint" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try testing.expectEqual(lb.endpoints.items.len, 1);
    try testing.expectEqualStrings(lb.endpoints.items[0].host, "host1");
    try testing.expectEqual(lb.endpoints.items[0].port, 23);
    try testing.expectEqual(lb.endpoints.items[0].weight, 1);
}

test "LoadBalancer: remove endpoint" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try testing.expectEqual(lb.endpoints.items.len, 1);

    const removed = lb.remove_endpoint("host1");
    try testing.expect(removed);
    try testing.expectEqual(lb.endpoints.items.len, 0);
}

test "LoadBalancer: round-robin distribution" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);
    try lb.add_endpoint("host3", 23, 1);

    lb.set_strategy(.round_robin);

    const ep1 = try lb.select_endpoint(.round_robin);
    const ep2 = try lb.select_endpoint(.round_robin);
    const ep3 = try lb.select_endpoint(.round_robin);
    const ep4 = try lb.select_endpoint(.round_robin);

    // Should cycle through endpoints
    try testing.expectEqualStrings(ep1.host, "host1");
    try testing.expectEqualStrings(ep2.host, "host2");
    try testing.expectEqualStrings(ep3.host, "host3");
    try testing.expectEqualStrings(ep4.host, "host1");
}

test "LoadBalancer: weighted round-robin distribution" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 2);

    lb.set_strategy(.weighted_round_robin);

    var host1_count: u32 = 0;
    var host2_count: u32 = 0;

    for (0..30) |_| {
        const ep = try lb.select_endpoint(.weighted_round_robin);
        if (std.mem.eql(u8, ep.host, "host1")) {
            host1_count += 1;
        } else {
            host2_count += 1;
        }
    }

    // host2 should get roughly 2x more requests (weight=2)
    try testing.expect(host2_count > host1_count);
}

test "LoadBalancer: least connections selection" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    // Manually set active sessions
    if (lb.get_endpoint("host1")) |ep| {
        ep.active_sessions = 5;
    }

    const ep = try lb.select_endpoint(.least_connections);
    try testing.expectEqualStrings(ep.host, "host2");
}

test "LoadBalancer: least response time selection" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    lb.record_response_time("host1", 100);
    lb.record_response_time("host2", 50);

    const ep = try lb.select_endpoint(.least_response_time);
    try testing.expectEqualStrings(ep.host, "host2");
}

test "LoadBalancer: no healthy endpoints error" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    lb.set_health_status("host1", .unhealthy);

    const result = lb.select_endpoint(.round_robin);
    try testing.expectError(error.NoHealthyEndpointsAvailable, result);
}

test "LoadBalancer: statistics tracking" {
    var lb = try LoadBalancer.init(testing.allocator);
    defer lb.deinit();

    try lb.add_endpoint("host1", 23, 1);
    try lb.add_endpoint("host2", 23, 1);

    _ = try lb.select_endpoint(.round_robin);
    _ = try lb.select_endpoint(.round_robin);

    const stats = lb.get_stats();
    try testing.expectEqual(stats.total_requests, 2);
    try testing.expectEqual(stats.successful_requests, 2);
}
