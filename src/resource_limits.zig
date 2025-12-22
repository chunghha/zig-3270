/// Resource management and limits enforcement for DoS prevention and stability.
/// Tracks and enforces limits on concurrent sessions, connections, and memory usage.
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Resource limit errors
pub const ResourceError = error{
    MaxSessionsExceeded,
    MaxConnectionsExceeded,
    MaxPendingCommandsExceeded,
    MemoryLimitExceeded,
    MaxFieldsExceeded,
    CommandQueueFull,
};

/// Resource limit configuration
pub const ResourceLimits = struct {
    max_concurrent_sessions: usize = 1000,
    max_connections_per_endpoint: usize = 100,
    max_pending_commands_per_session: usize = 1000,
    max_memory_bytes: u64 = 1024 * 1024 * 1024, // 1GB
    max_fields_per_screen: usize = 10000,
    max_command_queue_size: usize = 10000,

    pub fn validate(self: ResourceLimits) !void {
        if (self.max_concurrent_sessions == 0) return error.InvalidInput;
        if (self.max_connections_per_endpoint == 0) return error.InvalidInput;
        if (self.max_memory_bytes == 0) return error.InvalidInput;
    }
};

/// Session usage tracker
pub const SessionUsageTracker = struct {
    allocator: Allocator,
    max_sessions: usize,
    active_sessions: usize = 0,
    total_created: u64 = 0,
    peak_sessions: usize = 0,

    pub fn init(allocator: Allocator, max_sessions: usize) !SessionUsageTracker {
        return SessionUsageTracker{
            .allocator = allocator,
            .max_sessions = max_sessions,
        };
    }

    pub fn create_session(self: *SessionUsageTracker) ResourceError!void {
        if (self.active_sessions >= self.max_sessions) {
            return ResourceError.MaxSessionsExceeded;
        }
        self.active_sessions += 1;
        self.total_created += 1;
        if (self.active_sessions > self.peak_sessions) {
            self.peak_sessions = self.active_sessions;
        }
    }

    pub fn destroy_session(self: *SessionUsageTracker) void {
        if (self.active_sessions > 0) {
            self.active_sessions -= 1;
        }
    }

    pub fn get_stats(self: SessionUsageTracker) SessionStats {
        return SessionStats{
            .active = self.active_sessions,
            .total_created = self.total_created,
            .peak = self.peak_sessions,
            .available = self.max_sessions - self.active_sessions,
        };
    }
};

pub const SessionStats = struct {
    active: usize,
    total_created: u64,
    peak: usize,
    available: usize,
};

/// Connection usage tracker
pub const ConnectionUsageTracker = struct {
    allocator: Allocator,
    max_connections: usize,
    active_connections: usize = 0,
    total_created: u64 = 0,
    failed_connection_attempts: u64 = 0,

    pub fn init(allocator: Allocator, max_connections: usize) !ConnectionUsageTracker {
        return ConnectionUsageTracker{
            .allocator = allocator,
            .max_connections = max_connections,
        };
    }

    pub fn create_connection(self: *ConnectionUsageTracker) ResourceError!void {
        if (self.active_connections >= self.max_connections) {
            return ResourceError.MaxConnectionsExceeded;
        }
        self.active_connections += 1;
        self.total_created += 1;
    }

    pub fn close_connection(self: *ConnectionUsageTracker) void {
        if (self.active_connections > 0) {
            self.active_connections -= 1;
        }
    }

    pub fn record_failed_attempt(self: *ConnectionUsageTracker) void {
        self.failed_connection_attempts += 1;
    }

    pub fn get_stats(self: ConnectionUsageTracker) ConnectionStats {
        return ConnectionStats{
            .active = self.active_connections,
            .total_created = self.total_created,
            .failed_attempts = self.failed_connection_attempts,
            .available = self.max_connections - self.active_connections,
        };
    }
};

pub const ConnectionStats = struct {
    active: usize,
    total_created: u64,
    failed_attempts: u64,
    available: usize,
};

/// Memory usage tracker
pub const MemoryUsageTracker = struct {
    allocator: Allocator,
    max_memory: u64,
    current_usage: u64 = 0,
    peak_usage: u64 = 0,
    total_allocated: u64 = 0,
    total_freed: u64 = 0,

    pub fn init(allocator: Allocator, max_memory: u64) !MemoryUsageTracker {
        return MemoryUsageTracker{
            .allocator = allocator,
            .max_memory = max_memory,
        };
    }

    pub fn allocate(self: *MemoryUsageTracker, size: u64) ResourceError!void {
        if (self.current_usage + size > self.max_memory) {
            return ResourceError.MemoryLimitExceeded;
        }
        self.current_usage += size;
        self.total_allocated += size;
        if (self.current_usage > self.peak_usage) {
            self.peak_usage = self.current_usage;
        }
    }

    pub fn deallocate(self: *MemoryUsageTracker, size: u64) void {
        if (self.current_usage >= size) {
            self.current_usage -= size;
        }
        self.total_freed += size;
    }

    pub fn get_stats(self: MemoryUsageTracker) MemoryStats {
        return MemoryStats{
            .current_usage = self.current_usage,
            .peak_usage = self.peak_usage,
            .total_allocated = self.total_allocated,
            .total_freed = self.total_freed,
            .available = self.max_memory - self.current_usage,
            .utilization_percent = (self.current_usage * 100) / self.max_memory,
        };
    }
};

pub const MemoryStats = struct {
    current_usage: u64,
    peak_usage: u64,
    total_allocated: u64,
    total_freed: u64,
    available: u64,
    utilization_percent: u64,
};

/// Command queue tracker
pub const CommandQueueTracker = struct {
    max_queue_size: usize,
    pending_commands: usize = 0,
    total_processed: u64 = 0,
    dropped_commands: u64 = 0,

    pub fn enqueue(self: *CommandQueueTracker) ResourceError!void {
        if (self.pending_commands >= self.max_queue_size) {
            self.dropped_commands += 1;
            return ResourceError.CommandQueueFull;
        }
        self.pending_commands += 1;
    }

    pub fn dequeue(self: *CommandQueueTracker) void {
        if (self.pending_commands > 0) {
            self.pending_commands -= 1;
        }
        self.total_processed += 1;
    }

    pub fn get_stats(self: CommandQueueTracker) CommandQueueStats {
        return CommandQueueStats{
            .pending = self.pending_commands,
            .total_processed = self.total_processed,
            .dropped = self.dropped_commands,
            .capacity = self.max_queue_size - self.pending_commands,
        };
    }
};

pub const CommandQueueStats = struct {
    pending: usize,
    total_processed: u64,
    dropped: u64,
    capacity: usize,
};

/// Field limit tracker
pub const FieldLimitTracker = struct {
    max_fields: usize,
    current_fields: usize = 0,
    peak_fields: usize = 0,
    total_created: u64 = 0,

    pub fn create_field(self: *FieldLimitTracker) ResourceError!void {
        if (self.current_fields >= self.max_fields) {
            return ResourceError.MaxFieldsExceeded;
        }
        self.current_fields += 1;
        self.total_created += 1;
        if (self.current_fields > self.peak_fields) {
            self.peak_fields = self.current_fields;
        }
    }

    pub fn destroy_field(self: *FieldLimitTracker) void {
        if (self.current_fields > 0) {
            self.current_fields -= 1;
        }
    }

    pub fn get_stats(self: FieldLimitTracker) FieldStats {
        return FieldStats{
            .current = self.current_fields,
            .peak = self.peak_fields,
            .total_created = self.total_created,
            .available = self.max_fields - self.current_fields,
        };
    }
};

pub const FieldStats = struct {
    current: usize,
    peak: usize,
    total_created: u64,
    available: usize,
};

/// Combined resource manager
pub const ResourceManager = struct {
    allocator: Allocator,
    limits: ResourceLimits,
    sessions: SessionUsageTracker,
    connections: ConnectionUsageTracker,
    memory: MemoryUsageTracker,
    queue: CommandQueueTracker,
    fields: FieldLimitTracker,

    pub fn init(allocator: Allocator, limits: ResourceLimits) !ResourceManager {
        try limits.validate();

        return ResourceManager{
            .allocator = allocator,
            .limits = limits,
            .sessions = try SessionUsageTracker.init(allocator, limits.max_concurrent_sessions),
            .connections = try ConnectionUsageTracker.init(allocator, limits.max_connections_per_endpoint),
            .memory = try MemoryUsageTracker.init(allocator, limits.max_memory_bytes),
            .queue = CommandQueueTracker{ .max_queue_size = limits.max_command_queue_size },
            .fields = FieldLimitTracker{ .max_fields = limits.max_fields_per_screen },
        };
    }

    pub fn get_all_stats(self: ResourceManager) AllResourceStats {
        return AllResourceStats{
            .sessions = self.sessions.get_stats(),
            .connections = self.connections.get_stats(),
            .memory = self.memory.get_stats(),
            .queue = self.queue.get_stats(),
            .fields = self.fields.get_stats(),
        };
    }

    pub fn is_healthy(self: ResourceManager) bool {
        const stats = self.get_all_stats();
        // System is healthy if utilization is below 90%
        return stats.memory.utilization_percent < 90 and
            stats.sessions.active < (self.limits.max_concurrent_sessions * 90 / 100);
    }
};

pub const AllResourceStats = struct {
    sessions: SessionStats,
    connections: ConnectionStats,
    memory: MemoryStats,
    queue: CommandQueueStats,
    fields: FieldStats,
};

// ============================================================================
// TESTS
// ============================================================================

test "SessionUsageTracker tracks session creation" {
    const allocator = testing.allocator;
    var tracker = try SessionUsageTracker.init(allocator, 10);

    // Create sessions up to limit
    for (0..10) |_| {
        try tracker.create_session();
    }

    // Next should fail
    try testing.expectError(
        ResourceError.MaxSessionsExceeded,
        tracker.create_session(),
    );

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 10), stats.active);
    try testing.expectEqual(@as(usize, 10), stats.peak);
}

test "SessionUsageTracker tracks session destruction" {
    const allocator = testing.allocator;
    var tracker = try SessionUsageTracker.init(allocator, 10);

    try tracker.create_session();
    try tracker.create_session();
    tracker.destroy_session();

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 1), stats.active);
    try testing.expectEqual(@as(usize, 2), stats.peak);
    try testing.expectEqual(@as(usize, 2), stats.total_created);
}

test "ConnectionUsageTracker tracks connections" {
    const allocator = testing.allocator;
    var tracker = try ConnectionUsageTracker.init(allocator, 50);

    for (0..50) |_| {
        try tracker.create_connection();
    }

    try testing.expectError(
        ResourceError.MaxConnectionsExceeded,
        tracker.create_connection(),
    );

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 50), stats.active);
}

test "ConnectionUsageTracker tracks failed attempts" {
    const allocator = testing.allocator;
    var tracker = try ConnectionUsageTracker.init(allocator, 10);

    tracker.record_failed_attempt();
    tracker.record_failed_attempt();

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(u64, 2), stats.failed_attempts);
}

test "MemoryUsageTracker enforces memory limit" {
    const allocator = testing.allocator;
    var tracker = try MemoryUsageTracker.init(allocator, 1000);

    try tracker.allocate(500);
    try tracker.allocate(500);

    try testing.expectError(
        ResourceError.MemoryLimitExceeded,
        tracker.allocate(1),
    );

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(u64, 1000), stats.current_usage);
    try testing.expectEqual(@as(u64, 1000), stats.peak_usage);
}

test "MemoryUsageTracker tracks deallocation" {
    const allocator = testing.allocator;
    var tracker = try MemoryUsageTracker.init(allocator, 1000);

    try tracker.allocate(600);
    tracker.deallocate(300);

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(u64, 300), stats.current_usage);
    try testing.expectEqual(@as(u64, 600), stats.peak_usage);
    try testing.expectEqual(@as(u64, 600), stats.total_allocated);
    try testing.expectEqual(@as(u64, 300), stats.total_freed);
}

test "CommandQueueTracker enforces queue size" {
    var tracker = CommandQueueTracker{ .max_queue_size = 100 };

    for (0..100) |_| {
        try tracker.enqueue();
    }

    try testing.expectError(
        ResourceError.CommandQueueFull,
        tracker.enqueue(),
    );

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 100), stats.pending);
}

test "CommandQueueTracker tracks dequeue and processed commands" {
    var tracker = CommandQueueTracker{ .max_queue_size = 100 };

    try tracker.enqueue();
    try tracker.enqueue();
    tracker.dequeue();

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 1), stats.pending);
    try testing.expectEqual(@as(u64, 1), stats.total_processed);
}

test "FieldLimitTracker enforces field limits" {
    var tracker = FieldLimitTracker{ .max_fields = 100 };

    for (0..100) |_| {
        try tracker.create_field();
    }

    try testing.expectError(
        ResourceError.MaxFieldsExceeded,
        tracker.create_field(),
    );

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 100), stats.current);
    try testing.expectEqual(@as(usize, 100), stats.peak);
}

test "FieldLimitTracker tracks field destruction" {
    var tracker = FieldLimitTracker{ .max_fields = 100 };

    try tracker.create_field();
    try tracker.create_field();
    tracker.destroy_field();

    const stats = tracker.get_stats();
    try testing.expectEqual(@as(usize, 1), stats.current);
    try testing.expectEqual(@as(usize, 2), stats.peak);
}

test "ResourceManager initializes with limits" {
    const allocator = testing.allocator;
    const limits = ResourceLimits{
        .max_concurrent_sessions = 100,
        .max_connections_per_endpoint = 50,
    };

    var manager = try ResourceManager.init(allocator, limits);
    const stats = manager.get_all_stats();

    try testing.expectEqual(@as(usize, 0), stats.sessions.active);
    try testing.expectEqual(@as(usize, 0), stats.connections.active);
}

test "ResourceManager reports health status" {
    const allocator = testing.allocator;
    const limits = ResourceLimits{
        .max_concurrent_sessions = 100,
        .max_memory_bytes = 1000,
    };

    var manager = try ResourceManager.init(allocator, limits);

    // Healthy when usage is low
    try testing.expect(manager.is_healthy());

    // Allocate memory to reach 95%
    try manager.memory.allocate(950);

    // Should be unhealthy
    try testing.expect(!manager.is_healthy());
}
