/// Session Migration Manager
///
/// Handles migration of active sessions between different endpoints.
/// Enables failover, load balancing, and dynamic server migration.
///
/// Usage:
/// ```zig
/// var migrator = try SessionMigrator.init(allocator, &pool, &lifecycle);
/// defer migrator.deinit();
///
/// try migrator.migrate(session_id, "new_host", 23);
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const session_pool = @import("session_pool.zig");
const session_lifecycle = @import("session_lifecycle.zig");

pub const MigrationStatus = enum {
    pending,
    in_progress,
    snapshot_created,
    reconnecting,
    state_restored,
    completed,
    failed,
    rolled_back,
};

pub const Migration = struct {
    source_session_id: []const u8,
    source_host: []const u8,
    source_port: u16,
    target_host: []const u8,
    target_port: u16,
    snapshot: session_lifecycle.SessionSnapshot,
    status: MigrationStatus,
    error_message: ?[]const u8 = null,
    created_at: i64,
    completed_at: ?i64 = null,

    /// Allocator for this migration
    allocator: Allocator,

    pub fn deinit(self: *Migration) void {
        self.allocator.free(self.source_session_id);
        self.allocator.free(self.source_host);
        self.allocator.free(self.target_host);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        self.snapshot.deinit();
    }
};

pub const SessionMigrator = struct {
    pool: *session_pool.SessionPool,
    lifecycle: *session_lifecycle.LifecycleManager,
    allocator: Allocator,
    migrations: std.StringHashMap(Migration),
    active_migrations: u32 = 0,
    completed_migrations: u32 = 0,
    failed_migrations: u32 = 0,
    mutex: std.Thread.Mutex = .{},

    pub fn init(
        allocator: Allocator,
        pool: *session_pool.SessionPool,
        lifecycle: *session_lifecycle.LifecycleManager,
    ) SessionMigrator {
        return .{
            .pool = pool,
            .lifecycle = lifecycle,
            .allocator = allocator,
            .migrations = std.StringHashMap(Migration).init(allocator),
        };
    }

    pub fn deinit(self: *SessionMigrator) void {
        var iter = self.migrations.valueIterator();
        while (iter.next()) |migration| {
            migration.deinit();
        }
        self.migrations.deinit();
    }

    /// Start migration of session to new endpoint
    pub fn migrate(
        self: *SessionMigrator,
        session_id: []const u8,
        target_host: []const u8,
        target_port: u16,
    ) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Get source session
        const source_session = self.pool.get_session(session_id) orelse
            return error.SessionNotFound;

        // Create snapshot of current state
        const snapshot = try self.lifecycle.create_snapshot(session_id);

        // Generate migration ID
        const migration_id = try std.fmt.allocPrint(
            self.allocator,
            "{s}-mig-{d}",
            .{ session_id, std.time.milliTimestamp() },
        );

        const source_host = try self.allocator.dupe(u8, source_session.metadata.host);
        const target_host_copy = try self.allocator.dupe(u8, target_host);

        const migration = Migration{
            .source_session_id = try self.allocator.dupe(u8, session_id),
            .source_host = source_host,
            .source_port = source_session.metadata.port,
            .target_host = target_host_copy,
            .target_port = target_port,
            .snapshot = snapshot,
            .status = .pending,
            .created_at = std.time.milliTimestamp(),
            .allocator = self.allocator,
        };

        try self.migrations.put(migration_id, migration);
        self.active_migrations += 1;

        return migration_id;
    }

    /// Mark migration as in progress
    pub fn set_status(
        self: *SessionMigrator,
        migration_id: []const u8,
        status: MigrationStatus,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.migrations.getPtr(migration_id)) |migration| {
            migration.status = status;
            if (status == .completed or status == .failed or status == .rolled_back) {
                migration.completed_at = std.time.milliTimestamp();
            }
        } else {
            return error.MigrationNotFound;
        }
    }

    /// Set error message for failed migration
    pub fn set_error(
        self: *SessionMigrator,
        migration_id: []const u8,
        error_msg: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.migrations.getPtr(migration_id)) |migration| {
            if (migration.error_message) |msg| {
                self.allocator.free(msg);
            }
            migration.error_message = try self.allocator.dupe(u8, error_msg);
        } else {
            return error.MigrationNotFound;
        }
    }

    /// Verify session state consistency after migration
    pub fn verify_state(
        self: *SessionMigrator,
        migration_id: []const u8,
    ) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const migration = self.migrations.get(migration_id) orelse
            return error.MigrationNotFound;

        const session = self.pool.get_session(migration.source_session_id) orelse
            return false;

        // Check that metadata matches snapshot
        return std.mem.eql(u8, session.metadata.host, migration.target_host) and
            session.metadata.port == migration.target_port;
    }

    /// Rollback migration (restore to source)
    pub fn rollback(
        self: *SessionMigrator,
        migration_id: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const migration = self.migrations.getPtr(migration_id) orelse
            return error.MigrationNotFound;

        // Update session back to source
        try self.pool.set_state(migration.source_session_id, .connected);

        migration.status = .rolled_back;
        migration.completed_at = std.time.milliTimestamp();
    }

    /// Get migration by ID
    pub fn get_migration(self: *SessionMigrator, migration_id: []const u8) ?Migration {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.migrations.get(migration_id);
    }

    /// List all active migrations
    pub fn active_migrations_list(self: *SessionMigrator, allocator: Allocator) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList([]const u8).init(allocator);

        var iter = self.migrations.keyIterator();
        while (iter.next()) |key| {
            const migration = self.migrations.get(key.*).?;
            if (migration.status == .pending or migration.status == .in_progress) {
                try result.append(key.*);
            }
        }

        return result.toOwnedSlice();
    }

    /// Complete migration successfully
    pub fn complete_migration(
        self: *SessionMigrator,
        migration_id: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.migrations.getPtr(migration_id)) |migration| {
            migration.status = .completed;
            migration.completed_at = std.time.milliTimestamp();
            self.active_migrations -= 1;
            self.completed_migrations += 1;
        } else {
            return error.MigrationNotFound;
        }
    }

    /// Mark migration as failed
    pub fn fail_migration(
        self: *SessionMigrator,
        migration_id: []const u8,
        error_msg: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.migrations.getPtr(migration_id)) |migration| {
            migration.status = .failed;
            migration.completed_at = std.time.milliTimestamp();
            migration.error_message = try self.allocator.dupe(u8, error_msg);
            self.active_migrations -= 1;
            self.failed_migrations += 1;
        } else {
            return error.MigrationNotFound;
        }
    }

    /// Get migration statistics
    pub fn stats(self: *SessionMigrator) MigrationStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .total_migrations = @intCast(self.migrations.count()),
            .active_migrations = self.active_migrations,
            .completed_migrations = self.completed_migrations,
            .failed_migrations = self.failed_migrations,
        };
    }
};

pub const MigrationStats = struct {
    total_migrations: u32 = 0,
    active_migrations: u32 = 0,
    completed_migrations: u32 = 0,
    failed_migrations: u32 = 0,
};

// Tests
const testing = std.testing;

test "SessionMigrator: init and deinit" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var lifecycle = session_lifecycle.LifecycleManager.init(testing.allocator, &pool);
    defer lifecycle.deinit();

    var migrator = SessionMigrator.init(testing.allocator, &pool, &lifecycle);
    defer migrator.deinit();

    const s = migrator.stats();
    try testing.expectEqual(s.total_migrations, 0);
}

test "SessionMigrator: start migration" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var lifecycle = session_lifecycle.LifecycleManager.init(testing.allocator, &pool);
    defer lifecycle.deinit();

    var migrator = SessionMigrator.init(testing.allocator, &pool, &lifecycle);
    defer migrator.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const migration_id = try migrator.migrate(session_id, "newhost", 23);
    defer testing.allocator.free(migration_id);

    try testing.expectEqual(migrator.stats().total_migrations, 1);
}

test "SessionMigrator: set migration status" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var lifecycle = session_lifecycle.LifecycleManager.init(testing.allocator, &pool);
    defer lifecycle.deinit();

    var migrator = SessionMigrator.init(testing.allocator, &pool, &lifecycle);
    defer migrator.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const migration_id = try migrator.migrate(session_id, "newhost", 23);
    defer testing.allocator.free(migration_id);

    try migrator.set_status(migration_id, .in_progress);

    const migration = migrator.get_migration(migration_id);
    try testing.expect(migration != null);
    try testing.expectEqual(migration.?.status, .in_progress);
}

test "SessionMigrator: complete migration" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var lifecycle = session_lifecycle.LifecycleManager.init(testing.allocator, &pool);
    defer lifecycle.deinit();

    var migrator = SessionMigrator.init(testing.allocator, &pool, &lifecycle);
    defer migrator.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const migration_id = try migrator.migrate(session_id, "newhost", 23);
    defer testing.allocator.free(migration_id);

    try migrator.complete_migration(migration_id);

    const s = migrator.stats();
    try testing.expectEqual(s.completed_migrations, 1);
    try testing.expectEqual(s.active_migrations, 0);
}

test "SessionMigrator: fail migration" {
    var pool = session_pool.SessionPool.init(testing.allocator, 10);
    defer pool.deinit();

    var lifecycle = session_lifecycle.LifecycleManager.init(testing.allocator, &pool);
    defer lifecycle.deinit();

    var migrator = SessionMigrator.init(testing.allocator, &pool, &lifecycle);
    defer migrator.deinit();

    const session_id = try pool.create_session("localhost", 23, "user");
    defer pool.destroy_session(session_id);

    const migration_id = try migrator.migrate(session_id, "newhost", 23);
    defer testing.allocator.free(migration_id);

    try migrator.fail_migration(migration_id, "Connection refused");

    const s = migrator.stats();
    try testing.expectEqual(s.failed_migrations, 1);
}
