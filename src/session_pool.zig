/// Session Pool Manager
///
/// Manages multiple concurrent TN3270 sessions with lifecycle tracking,
/// session state persistence, and concurrent access safety.
///
/// Usage:
/// ```zig
/// var pool = SessionPool.init(allocator, 10);
/// defer pool.deinit();
///
/// const session_id = try pool.create_session("host", 23, "user");
/// defer pool.destroy_session(session_id);
///
/// const session = pool.get_session(session_id).?;
/// try session.connect();
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SessionState = enum {
    initializing,
    connected,
    active,
    idle,
    suspended,
    closed,
    error_state,
};

pub const SessionMetadata = struct {
    host: []const u8,
    port: u16,
    application: ?[]const u8 = null,
    user: ?[]const u8 = null,
    connection_count: u32 = 0,
};

pub const ManagedSession = struct {
    id: []const u8,
    state: SessionState,
    created_at: i64,
    last_activity: i64,
    metadata: SessionMetadata,
};

pub const SessionPool = struct {
    sessions: std.StringHashMap(ManagedSession),
    allocator: Allocator,
    max_sessions: u32,
    idle_timeout_ms: u64,
    next_session_id: u32 = 1,
    mutex: std.Thread.Mutex = .{},

    /// Initialize session pool with given capacity and timeout
    pub fn init(allocator: Allocator, max_sessions: u32) SessionPool {
        return .{
            .sessions = std.StringHashMap(ManagedSession).init(allocator),
            .allocator = allocator,
            .max_sessions = max_sessions,
            .idle_timeout_ms = 5 * 60 * 1000, // 5 minutes default
        };
    }

    /// Deinitialize pool and cleanup all sessions
    pub fn deinit(self: *SessionPool) void {
        var iter = self.sessions.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.sessions.deinit();
    }

    /// Create new session with metadata
    /// Returns allocated session ID that must be freed by caller
    pub fn create_session(
        self: *SessionPool,
        host: []const u8,
        port: u16,
        user: ?[]const u8,
    ) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.count() >= self.max_sessions) {
            return error.PoolFull;
        }

        // Generate session ID
        const session_id = try std.fmt.allocPrint(
            self.allocator,
            "sess-{d:0>6}",
            .{self.next_session_id},
        );
        self.next_session_id += 1;

        // Copy metadata strings
        const host_copy = try self.allocator.dupe(u8, host);
        const user_copy = if (user) |u| try self.allocator.dupe(u8, u) else null;

        const now = std.time.milliTimestamp();
        const session = ManagedSession{
            .id = session_id,
            .state = .initializing,
            .created_at = now,
            .last_activity = now,
            .metadata = .{
                .host = host_copy,
                .port = port,
                .user = user_copy,
                .connection_count = 0,
            },
        };

        try self.sessions.put(session_id, session);
        return session_id;
    }

    /// Get session by ID
    pub fn get_session(self: *SessionPool, session_id: []const u8) ?ManagedSession {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sessions.get(session_id);
    }

    /// Update session state
    pub fn set_state(
        self: *SessionPool,
        session_id: []const u8,
        state: SessionState,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(session_id)) |session| {
            session.state = state;
            session.last_activity = std.time.milliTimestamp();
        } else {
            return error.SessionNotFound;
        }
    }

    /// Record activity to update last_activity timestamp
    pub fn record_activity(self: *SessionPool, session_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(session_id)) |session| {
            session.last_activity = std.time.milliTimestamp();
        } else {
            return error.SessionNotFound;
        }
    }

    /// Increment connection count for session
    pub fn increment_connection_count(self: *SessionPool, session_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(session_id)) |session| {
            session.metadata.connection_count += 1;
        } else {
            return error.SessionNotFound;
        }
    }

    /// Destroy session and free resources
    pub fn destroy_session(self: *SessionPool, session_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.fetchRemove(session_id)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.metadata.host);
            if (entry.value.metadata.user) |user| {
                self.allocator.free(user);
            }
        }
    }

    /// Count active sessions
    pub fn count(self: *SessionPool) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return @intCast(self.sessions.count());
    }

    /// Get sessions with specific state
    pub fn get_sessions_by_state(
        self: *SessionPool,
        state: SessionState,
        allocator: Allocator,
    ) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList([]const u8).init(allocator);

        var iter = self.sessions.valueIterator();
        while (iter.next()) |session| {
            if (session.state == state) {
                try result.append(session.id);
            }
        }

        return result.toOwnedSlice();
    }

    /// Get all session IDs
    pub fn all_sessions(self: *SessionPool, allocator: Allocator) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList([]const u8).init(allocator);

        var iter = self.sessions.keyIterator();
        while (iter.next()) |key| {
            try result.append(key.*);
        }

        return result.toOwnedSlice();
    }

    /// Pool statistics
    pub fn stats(self: *SessionPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats_result = PoolStats{
            .total_sessions = @intCast(self.sessions.count()),
        };

        var iter = self.sessions.valueIterator();
        while (iter.next()) |session| {
            switch (session.state) {
                .initializing => stats_result.initializing_count += 1,
                .connected => stats_result.connected_count += 1,
                .active => stats_result.active_count += 1,
                .idle => stats_result.idle_count += 1,
                .suspended => stats_result.suspended_count += 1,
                .closed => stats_result.closed_count += 1,
                .error_state => stats_result.error_count += 1,
            }
        }

        return stats_result;
    }

    /// Set idle timeout in milliseconds
    pub fn set_idle_timeout_ms(self: *SessionPool, timeout_ms: u64) void {
        self.idle_timeout_ms = timeout_ms;
    }
};

pub const PoolStats = struct {
    total_sessions: u32 = 0,
    initializing_count: u32 = 0,
    connected_count: u32 = 0,
    active_count: u32 = 0,
    idle_count: u32 = 0,
    suspended_count: u32 = 0,
    closed_count: u32 = 0,
    error_count: u32 = 0,
};

// Tests
const testing = std.testing;

test "SessionPool: init and deinit" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    try testing.expectEqual(pool.max_sessions, 10);
    try testing.expectEqual(pool.count(), 0);
}

test "SessionPool: create session" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    try testing.expectEqual(pool.count(), 1);
}

test "SessionPool: get session" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const session = pool.get_session(session_id);
    try testing.expect(session != null);
    try testing.expectEqualStrings(session.?.metadata.host, "localhost");
    try testing.expectEqual(session.?.metadata.port, 23);
}

test "SessionPool: set session state" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    try pool.set_state(session_id, .connected);

    const session = pool.get_session(session_id).?;
    try testing.expectEqual(session.state, .connected);
}

test "SessionPool: destroy session" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    try testing.expectEqual(pool.count(), 1);

    pool.destroy_session(session_id);
    try testing.expectEqual(pool.count(), 0);
}

test "SessionPool: multiple sessions" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const id1 = try pool.create_session("host1", 23, "user1");
    const id2 = try pool.create_session("host2", 23, "user2");
    const id3 = try pool.create_session("host3", 23, "user3");

    defer pool.destroy_session(id1);
    defer pool.destroy_session(id2);
    defer pool.destroy_session(id3);

    try testing.expectEqual(pool.count(), 3);
}

test "SessionPool: pool full error" {
    var pool = SessionPool.init(testing.allocator, 2);
    defer pool.deinit();

    const id1 = try pool.create_session("host1", 23, "user1");
    const id2 = try pool.create_session("host2", 23, "user2");

    defer pool.destroy_session(id1);
    defer pool.destroy_session(id2);

    const result = pool.create_session("host3", 23, "user3");
    try testing.expectError(error.PoolFull, result);
}

test "SessionPool: stats" {
    var pool = SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    const id1 = try pool.create_session("host1", 23, "user1");
    const id2 = try pool.create_session("host2", 23, "user2");

    defer pool.destroy_session(id1);
    defer pool.destroy_session(id2);

    try pool.set_state(id1, .active);
    try pool.set_state(id2, .idle);

    const s = pool.stats();
    try testing.expectEqual(s.total_sessions, 2);
    try testing.expectEqual(s.active_count, 1);
    try testing.expectEqual(s.idle_count, 1);
}
