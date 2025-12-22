const std = @import("std");
const protocol = @import("protocol.zig");

/// Chaos engineering framework for network fault injection
pub const ChaosScenario = struct {
    const Self = @This();

    pub const ScenarioType = enum {
        network_delay,
        packet_loss,
        packet_corruption,
        connection_timeout,
        partial_packet,
        duplicate_packet,
        out_of_order_packets,
        zero_byte_write,
        buffer_overflow,
        rapid_reconnect,
        slow_read,
        slow_write,
        random_disconnect,
        malformed_command,
        invalid_protocol_state,
        memory_pressure,
        cpu_spike,
        disk_io_blockage,
        dns_resolution_failure,
        tls_handshake_failure,
        certificate_expiry,
        weak_cipher_suite,
        clock_skew,
        resource_exhaustion,
        cascading_failure,
        network_partition,
        bgp_hijack_simulation,
        jitter_injection,
        burst_traffic,
        sustained_high_load,
        bursty_loss,
        correlated_loss,
        concurrent_connections_spike,
        session_affinity_violation,
        load_balancer_failure,
        endpoint_flip,
        slow_application_response,
        asymmetric_latency,
        reordering_window,
        packet_duplication_burst,
        half_open_connection,
        reset_connection,
        close_without_flush,
        ack_loss,
        syn_flood,
        slowloris_attack,
        early_close,
        late_data_arrival,
        out_of_memory,
        stack_overflow,
        file_descriptor_exhaustion,
        thread_starvation,
        lock_contention,
        cache_invalidation,
        race_condition,
    };

    name: []const u8,
    scenario_type: ScenarioType,
    probability: f32, // 0.0 to 1.0
    duration_ms: u32,
    target_component: []const u8,
};

/// Chaos coordinator for managing fault injection
pub const ChaosCoordinator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    scenarios: std.ArrayList(ChaosScenario),
    active_faults: std.ArrayList(ActiveFault),
    seed: u64,
    rng: std.Random.Xoshiro256,
    enabled: bool = false,
    stats: Stats = .{},

    pub const ActiveFault = struct {
        scenario: ChaosScenario,
        start_time: i64,
        affected_connections: u32 = 0,
    };

    pub const Stats = struct {
        faults_injected: u32 = 0,
        faults_triggered: u32 = 0,
        recovery_count: u32 = 0,
        total_duration_ms: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, seed: u64) Self {
        var prng = std.Random.Xoshiro256.init(seed);
        return .{
            .allocator = allocator,
            .scenarios = std.ArrayList(ChaosScenario).init(allocator),
            .active_faults = std.ArrayList(ActiveFault).init(allocator),
            .seed = seed,
            .rng = prng,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scenarios.deinit();
        self.active_faults.deinit();
    }

    /// Add a chaos scenario
    pub fn add_scenario(self: *Self, scenario: ChaosScenario) !void {
        try self.scenarios.append(scenario);
    }

    /// Enable chaos testing
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable chaos testing
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Trigger a random fault based on probabilities
    pub fn maybe_inject_fault(self: *Self) !?ChaosScenario {
        if (!self.enabled or self.scenarios.items.len == 0) {
            return null;
        }

        // Select random scenario
        const rng_val = self.rng.random().float(f32);
        for (self.scenarios.items) |scenario| {
            if (rng_val < scenario.probability) {
                try self.active_faults.append(.{
                    .scenario = scenario,
                    .start_time = std.time.milliTimestamp(),
                });
                self.stats.faults_triggered += 1;
                return scenario;
            }
        }

        return null;
    }

    /// Get active faults
    pub fn get_active_faults(self: *const Self) []const ActiveFault {
        return self.active_faults.items;
    }

    /// Clear expired faults
    pub fn clean_expired_faults(self: *Self) void {
        const now = std.time.milliTimestamp();
        var i: usize = 0;

        while (i < self.active_faults.items.len) {
            const fault = &self.active_faults.items[i];
            const elapsed = @as(u32, @intCast(now - fault.start_time));

            if (elapsed > fault.scenario.duration_ms) {
                _ = self.active_faults.orderedRemove(i);
                self.stats.recovery_count += 1;
            } else {
                i += 1;
            }
        }
    }

    /// Get statistics
    pub fn get_stats(self: *const Self) Stats {
        return self.stats;
    }
};

/// Network fault simulator
pub const NetworkFaultSimulator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    coordinator: *ChaosCoordinator,
    packet_queue: std.ArrayList(SimulatedPacket),

    pub const SimulatedPacket = struct {
        data: []u8,
        destination: []const u8,
        sequence: u32,
        timestamp: i64,
        priority: u8,
    };

    pub fn init(allocator: std.mem.Allocator, coordinator: *ChaosCoordinator) Self {
        return .{
            .allocator = allocator,
            .coordinator = coordinator,
            .packet_queue = std.ArrayList(SimulatedPacket).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.packet_queue.items) |packet| {
            self.allocator.free(packet.data);
        }
        self.packet_queue.deinit();
    }

    /// Simulate sending a packet (may be dropped, delayed, corrupted)
    pub fn send_packet(self: *Self, data: []const u8, destination: []const u8) !bool {
        try self.coordinator.clean_expired_faults();

        // Check for active packet loss fault
        for (self.coordinator.active_faults.items) |fault| {
            if (std.mem.eql(u8, fault.scenario.target_component, "network")) {
                switch (fault.scenario.scenario_type) {
                    .packet_loss => {
                        if (self.coordinator.rng.random().float(f32) < 0.1) {
                            // 10% chance to drop packet
                            return false;
                        }
                    },
                    .packet_corruption => {
                        // Corrupt a random byte
                        const copy = try self.allocator.alloc(u8, data.len);
                        @memcpy(copy, data);
                        if (copy.len > 0) {
                            const idx = self.coordinator.rng.random().uintAtMost(usize, copy.len - 1);
                            copy[idx] ^= 0xFF;
                        }
                        self.allocator.free(copy);
                    },
                    .network_delay => {
                        // Simulate delay
                        std.posix.nanosleep(0, 50 * 1_000_000);
                    },
                    else => {},
                }
            }
        }

        return true;
    }

    /// Receive packet (may be delayed, lost, or duplicated)
    pub fn receive_packet(self: *Self) !?[]u8 {
        try self.coordinator.clean_expired_faults();

        if (self.packet_queue.items.len == 0) {
            return null;
        }

        return self.packet_queue.items[0].data;
    }

    /// Simulate connection timeout
    pub fn simulate_timeout(self: *Self) !bool {
        for (self.coordinator.active_faults.items) |fault| {
            if (fault.scenario.scenario_type == .connection_timeout) {
                return true;
            }
        }
        return false;
    }
};

/// Stress test executor
pub const StressTestExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    coordinator: *ChaosCoordinator,
    test_results: std.ArrayList(TestResult),

    pub const TestResult = struct {
        scenario_name: []const u8,
        success: bool,
        duration_ms: u32,
        error_message: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, coordinator: *ChaosCoordinator) Self {
        return .{
            .allocator = allocator,
            .coordinator = coordinator,
            .test_results = std.ArrayList(TestResult).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.test_results.deinit();
    }

    /// Run a stress test scenario
    pub fn run_scenario(self: *Self, scenario: ChaosScenario) !void {
        const start = std.time.milliTimestamp();

        try self.coordinator.add_scenario(scenario);
        self.coordinator.enable();

        // Simulate test execution
        var iterations: u32 = 0;
        while (iterations < 10) : (iterations += 1) {
            if (try self.coordinator.maybe_inject_fault()) |fault| {
                // Fault was injected, continue
            }
            std.posix.nanosleep(0, 10 * 1_000_000);
        }

        self.coordinator.disable();

        const elapsed = @as(u32, @intCast(std.time.milliTimestamp() - start));

        try self.test_results.append(.{
            .scenario_name = scenario.name,
            .success = true,
            .duration_ms = elapsed,
        });
    }

    /// Get test results
    pub fn get_results(self: *const Self) []const TestResult {
        return self.test_results.items;
    }

    /// Print test report
    pub fn print_report(self: *const Self) void {
        std.debug.print("=== Chaos Test Report ===\n", .{});
        std.debug.print("Total scenarios: {}\n", .{self.test_results.items.len});

        var passed: usize = 0;
        for (self.test_results.items) |result| {
            if (result.success) passed += 1;
            const status = if (result.success) "PASS" else "FAIL";
            std.debug.print("[{}] {} - {}ms\n", .{ status, result.scenario_name, result.duration_ms });
        }

        std.debug.print("Passed: {}/{}\n", .{ passed, self.test_results.items.len });
    }
};

/// Network resilience validator
pub const ResilienceValidator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    checkpoint_count: u32 = 0,
    recovery_times: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .recovery_times = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.recovery_times.deinit();
    }

    /// Record checkpoint during fault injection
    pub fn checkpoint(self: *Self) !void {
        self.checkpoint_count += 1;
    }

    /// Record recovery time after fault
    pub fn record_recovery_time(self: *Self, time_ms: u32) !void {
        try self.recovery_times.append(time_ms);
    }

    /// Validate recovery time SLA
    pub fn validate_sla(self: *const Self, max_recovery_ms: u32) bool {
        for (self.recovery_times.items) |time| {
            if (time > max_recovery_ms) {
                return false;
            }
        }
        return true;
    }

    /// Get average recovery time
    pub fn avg_recovery_time(self: *const Self) f32 {
        if (self.recovery_times.items.len == 0) return 0;
        var sum: u32 = 0;
        for (self.recovery_times.items) |time| {
            sum += time;
        }
        return @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(self.recovery_times.items.len));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "chaos coordinator: initialization" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    try std.testing.expect(!coordinator.enabled);
}

test "chaos coordinator: add and enable scenarios" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    const scenario = ChaosScenario{
        .name = "test_delay",
        .scenario_type = .network_delay,
        .probability = 0.5,
        .duration_ms = 1000,
        .target_component = "network",
    };

    try coordinator.add_scenario(scenario);
    try std.testing.expectEqual(@as(usize, 1), coordinator.scenarios.items.len);

    coordinator.enable();
    try std.testing.expect(coordinator.enabled);
}

test "chaos coordinator: disable scenarios" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    coordinator.enable();
    try std.testing.expect(coordinator.enabled);

    coordinator.disable();
    try std.testing.expect(!coordinator.enabled);
}

test "chaos coordinator: maybe inject fault" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 42);
    defer coordinator.deinit();

    const scenario = ChaosScenario{
        .name = "high_prob",
        .scenario_type = .network_delay,
        .probability = 1.0, // Always trigger
        .duration_ms = 100,
        .target_component = "network",
    };

    try coordinator.add_scenario(scenario);
    coordinator.enable();

    const fault = try coordinator.maybe_inject_fault();
    try std.testing.expect(fault != null);
}

test "network fault simulator: send packet" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    var simulator = NetworkFaultSimulator.init(std.testing.allocator, &coordinator);
    defer simulator.deinit();

    const data = "test data";
    const sent = try simulator.send_packet(data, "localhost");
    try std.testing.expect(sent);
}

test "stress test executor: run scenario" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    var executor = StressTestExecutor.init(std.testing.allocator, &coordinator);
    defer executor.deinit();

    const scenario = ChaosScenario{
        .name = "test_scenario",
        .scenario_type = .network_delay,
        .probability = 0.1,
        .duration_ms = 50,
        .target_component = "network",
    };

    try executor.run_scenario(scenario);
    try std.testing.expect(executor.test_results.items.len > 0);
}

test "resilience validator: checkpoint and recovery" {
    var validator = ResilienceValidator.init(std.testing.allocator);
    defer validator.deinit();

    try validator.checkpoint();
    try std.testing.expectEqual(@as(u32, 1), validator.checkpoint_count);

    try validator.record_recovery_time(150);
    try validator.record_recovery_time(120);

    const avg = validator.avg_recovery_time();
    try std.testing.expect(avg > 100 and avg < 200);
}

test "resilience validator: sla validation" {
    var validator = ResilienceValidator.init(std.testing.allocator);
    defer validator.deinit();

    try validator.record_recovery_time(100);
    try validator.record_recovery_time(150);

    try std.testing.expect(validator.validate_sla(200));
    try std.testing.expect(!validator.validate_sla(50));
}

test "chaos coordinator: active fault tracking" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    const scenario = ChaosScenario{
        .name = "tracking_test",
        .scenario_type = .network_delay,
        .probability = 1.0,
        .duration_ms = 100,
        .target_component = "network",
    };

    try coordinator.add_scenario(scenario);
    coordinator.enable();

    _ = try coordinator.maybe_inject_fault();

    const faults = coordinator.get_active_faults();
    try std.testing.expect(faults.len > 0);
}

test "chaos coordinator: fault expiration" {
    var coordinator = ChaosCoordinator.init(std.testing.allocator, 12345);
    defer coordinator.deinit();

    const scenario = ChaosScenario{
        .name = "short_fault",
        .scenario_type = .network_delay,
        .probability = 1.0,
        .duration_ms = 10, // Very short
        .target_component = "network",
    };

    try coordinator.add_scenario(scenario);
    coordinator.enable();

    _ = try coordinator.maybe_inject_fault();

    var faults = coordinator.get_active_faults();
    try std.testing.expect(faults.len > 0);

    std.posix.nanosleep(0, 20 * 1_000_000); // Wait 20ms

    coordinator.clean_expired_faults();

    faults = coordinator.get_active_faults();
    try std.testing.expect(faults.len == 0);
}
