/// Session Lifecycle Manager
///
/// Manages session lifecycle transitions with event hooks and state snapshots.
/// Enables pause/resume functionality and event-driven session management.
///
/// Usage:
/// ```zig
/// var manager = try LifecycleManager.init(allocator, &pool);
/// defer manager.deinit();
///
/// try manager.register_hook(.session_connected, on_session_connected);
/// try manager.transition_state(session_id, .connected);
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const session_pool = @import("session_pool.zig");

pub const SessionState = session_pool.SessionState;

pub const EventType = enum {
    session_created,
    session_connected,
    session_idle,
    session_suspended,
    session_resumed,
    session_closed,
    session_error,
};

pub const EventHook = *const fn (session_id: []const u8, state: SessionState) void;

pub const SessionSnapshot = struct {
    session_id: []const u8,
    state: SessionState,
    timestamp: i64,
    metadata: SessionMetadata,

    /// Allocator for this snapshot
    allocator: Allocator,

    pub fn deinit(self: *SessionSnapshot) void {
        self.allocator.free(self.session_id);
        self.allocator.free(self.metadata.host);
        if (self.metadata.user) |user| {
            self.allocator.free(user);
        }
    }
};

pub const SessionMetadata = struct {
    host: []const u8,
    port: u16,
    application: ?[]const u8 = null,
    user: ?[]const u8 = null,
    connection_count: u32 = 0,
};

pub const LifecycleManager = struct {
    pool: *session_pool.SessionPool,
    allocator: Allocator,
    hooks: std.EnumMap(EventType, ?EventHook) = std.EnumMap(EventType, ?EventHook){},
    snapshots: std.StringHashMap(SessionSnapshot),
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: Allocator, pool: *session_pool.SessionPool) LifecycleManager {
        return .{
            .pool = pool,
            .allocator = allocator,
            .snapshots = std.StringHashMap(SessionSnapshot).init(allocator),
        };
    }

    pub fn deinit(self: *LifecycleManager) void {
        var iter = self.snapshots.valueIterator();
        while (iter.next()) |snapshot| {
            snapshot.deinit();
        }
        self.snapshots.deinit();
    }

    /// Register event hook for a specific event type
    pub fn register_hook(self: *LifecycleManager, event_type: EventType, hook: EventHook) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.hooks.put(event_type, hook);
    }

    /// Unregister event hook
    pub fn unregister_hook(self: *LifecycleManager, event_type: EventType) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.hooks.put(event_type, null);
    }

    /// Transition session state and trigger event hooks
    pub fn transition_state(
        self: *LifecycleManager,
        session_id: []const u8,
        new_state: SessionState,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update state in pool
        try self.pool.set_state(session_id, new_state);

        // Determine event type from state transition
        const event_type: EventType = switch (new_state) {
            .connected => .session_connected,
            .idle => .session_idle,
            .suspended => .session_suspended,
            .closed => .session_closed,
            .error_state => .session_error,
            else => return,
        };

        // Trigger hook if registered
        if (self.hooks.get(event_type)) |hook| {
            if (hook) |h| {
                h(session_id, new_state);
            }
        }
    }

    /// Create session snapshot for persistence/recovery
    pub fn create_snapshot(self: *LifecycleManager, session_id: []const u8) !SessionSnapshot {
        self.mutex.lock();
        defer self.mutex.unlock();

        const session = self.pool.get_session(session_id) orelse return error.SessionNotFound;

        const id_copy = try self.allocator.dupe(u8, session.id);
        const host_copy = try self.allocator.dupe(u8, session.metadata.host);
        const user_copy = if (session.metadata.user) |user| try self.allocator.dupe(u8, user) else null;

        const snapshot = SessionSnapshot{
            .session_id = id_copy,
            .state = session.state,
            .timestamp = std.time.milliTimestamp(),
            .metadata = .{
                .host = host_copy,
                .port = session.metadata.port,
                .user = user_copy,
                .connection_count = session.metadata.connection_count,
            },
            .allocator = self.allocator,
        };

        return snapshot;
    }

    /// Store snapshot for later recovery
    pub fn store_snapshot(self: *LifecycleManager, snapshot: SessionSnapshot) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id_copy = try self.allocator.dupe(u8, snapshot.session_id);
        try self.snapshots.put(id_copy, snapshot);
    }

    /// Retrieve stored snapshot
    pub fn get_snapshot(self: *LifecycleManager, session_id: []const u8) ?SessionSnapshot {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.snapshots.get(session_id);
    }

    /// Suspend session (save state, don't close connection)
    pub fn suspend_session(self: *LifecycleManager, session_id: []const u8) !void {
        // Create snapshot before suspending
        const snapshot = try self.create_snapshot(session_id);
        try self.store_snapshot(snapshot);

        // Transition to suspended state
        try self.transition_state(session_id, .suspended);
    }

    /// Resume session from snapshot
    pub fn resume_session(self: *LifecycleManager, session_id: []const u8) !SessionSnapshot {
        self.mutex.lock();
        defer self.mutex.unlock();

        const snapshot = self.snapshots.get(session_id) orelse return error.SnapshotNotFound;

        // Transition to active state
        try self.pool.set_state(session_id, .active);

        return snapshot;
    }

    /// Suspend and delete snapshot
    pub fn clear_snapshot(self: *LifecycleManager, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.snapshots.fetchRemove(session_id)) |entry| {
            entry.value.deinit();
        }
    }

    /// Get lifecycle statistics
    pub fn stats(self: *LifecycleManager) LifecycleStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .total_snapshots = @intCast(self.snapshots.count()),
        };
    }
};

pub const LifecycleStats = struct {
    total_snapshots: u32 = 0,
};

// Tests
const testing = std.testing;

test "LifecycleManager: init and deinit" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const stats = manager.stats();
    try testing.expectEqual(stats.total_snapshots, 0);
}

test "LifecycleManager: register hook" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    var hook_called = false;
    const test_hook: EventHook = struct {
        var called: *bool = undefined;

        fn hook(_: []const u8, _: SessionState) void {
            called.* = true;
        }
    }.hook;

    test_hook.called = &hook_called;
    manager.register_hook(.session_connected, test_hook);

    try testing.expect(manager.hooks.get(.session_connected) != null);
}

test "LifecycleManager: create snapshot" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    var snapshot = try manager.create_snapshot(session_id);
    defer snapshot.deinit();

    try testing.expectEqualStrings(snapshot.metadata.host, "localhost");
    try testing.expectEqual(snapshot.metadata.port, 23);
}

test "LifecycleManager: store and retrieve snapshot" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const snapshot = try manager.create_snapshot(session_id);
    try manager.store_snapshot(snapshot);

    const retrieved = manager.get_snapshot(session_id);
    try testing.expect(retrieved != null);
    try testing.expectEqualStrings(retrieved.?.metadata.host, "localhost");
}

test "LifecycleManager: suspend and resume session" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    // Suspend session
    try manager.suspend_session(session_id);
    const session = pool.get_session(session_id).?;
    try testing.expectEqual(session.state, .suspended);

    // Resume session
    var resumed_snapshot = try manager.resume_session(session_id);
    defer resumed_snapshot.deinit();

    const resumed_session = pool.get_session(session_id).?;
    try testing.expectEqual(resumed_session.state, .active);
}

test "LifecycleManager: transition state" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    try manager.transition_state(session_id, .connected);

    const session = pool.get_session(session_id).?;
    try testing.expectEqual(session.state, .connected);
}

test "LifecycleManager: clear snapshot" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const snapshot = try manager.create_snapshot(session_id);
    try manager.store_snapshot(snapshot);

    try testing.expectEqual(manager.stats().total_snapshots, 1);

    manager.clear_snapshot(session_id);
    try testing.expectEqual(manager.stats().total_snapshots, 0);
}

test "LifecycleManager: multiple snapshots" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var manager = LifecycleManager.init(testing.allocator, &pool);
    defer manager.deinit();

    const id1 = try pool.create_session("host1", 23, "user1");
    const id2 = try pool.create_session("host2", 23, "user2");
    const id3 = try pool.create_session("host3", 23, "user3");

    defer pool.destroy_session(id1);
    defer pool.destroy_session(id2);
    defer pool.destroy_session(id3);

    const snap1 = try manager.create_snapshot(id1);
    const snap2 = try manager.create_snapshot(id2);
    const snap3 = try manager.create_snapshot(id3);

    try manager.store_snapshot(snap1);
    try manager.store_snapshot(snap2);
    try manager.store_snapshot(snap3);

    try testing.expectEqual(manager.stats().total_snapshots, 3);
}
