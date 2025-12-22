const std = @import("std");

pub const AuditEvent = struct {
    timestamp: i64,
    event_type: EventType,
    session_id: ?[]const u8,
    user: ?[]const u8,
    host: ?[]const u8,
    action: []const u8,
    details: ?[]const u8,
    status: EventStatus,
    err: ?[]const u8 = null,
};

pub const EventType = enum {
    session_created,
    session_connected,
    session_suspended,
    session_resumed,
    authentication,
    data_access,
    field_modification,
    session_closed,
    connection_error,
    security_event,
    admin_action,
};

pub const EventStatus = enum {
    success,
    failed,
    partial,
    denied,
};

pub const AuditLevel = enum {
    disabled,
    err,
    warn,
    info,
    debug,
};

pub const AuditConfig = struct {
    file_path: []const u8,
    max_file_size: u64 = 10_000_000, // 10MB default
    max_files: u32 = 10,
    log_level: AuditLevel = .info,
    include_network_details: bool = true,
    include_data_snapshots: bool = false,
};

pub const RetentionPolicy = struct {
    retention_days: u32 = 30,
    archive_days: u32 = 7,
    enable_compression: bool = true,
    enable_encryption: bool = false,
    secure_delete: bool = true,
};

pub const AuditLogger = struct {
    allocator: std.mem.Allocator,
    config: AuditConfig,
    file: ?std.fs.File = null,
    writer: ?std.io.BufferedWriter(4096, std.fs.File.Writer) = null,
    current_size: u64 = 0,
    event_count: u64 = 0,
    retention: RetentionPolicy = .{},
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, config: AuditConfig) !AuditLogger {
        var logger = AuditLogger{
            .allocator = allocator,
            .config = try allocator.dupe(u8, config.file_path),
        };
        logger.config.file_path = config.file_path;
        logger.config.max_file_size = config.max_file_size;
        logger.config.max_files = config.max_files;
        logger.config.log_level = config.log_level;
        logger.config.include_network_details = config.include_network_details;
        logger.config.include_data_snapshots = config.include_data_snapshots;

        try logger.openFile();
        return logger;
    }

    fn openFile(self: *AuditLogger) !void {
        var dir = try std.fs.cwd().makeOpenPath(
            std.fs.path.dirname(self.config.file_path) orelse ".",
            .{},
        );
        defer dir.close();

        const basename = std.fs.path.basename(self.config.file_path);
        self.file = try dir.createFile(basename, .{
            .read = true,
            .truncate = false,
        });

        self.current_size = try self.file.?.getEndPos();
    }

    pub fn logEvent(self: *AuditLogger, event: AuditEvent) !void {
        if (@intFromEnum(self.config.log_level) == 0) return; // disabled

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file == null) return;

        // Check for rotation
        try self.rotateIfNeeded();

        // Format event as JSON
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try std.json.stringify(
            event,
            .{ .whitespace = .minified },
            fbs.writer(),
        );

        const json_str = fbs.getWritten();

        // Write event with newline
        var writer = std.io.bufferedWriter(self.file.?.writer());
        try writer.writer().writeAll(json_str);
        try writer.writer().writeAll("\n");
        try writer.flush();

        self.current_size += json_str.len + 1;
        self.event_count += 1;
    }

    fn rotateIfNeeded(self: *AuditLogger) !void {
        if (self.current_size < self.config.max_file_size) return;

        // Close current file
        if (self.file) |f| {
            f.close();
        }

        // Rotate files
        var i: i32 = @intCast(self.config.max_files - 1);
        while (i > 0) : (i -= 1) {
            var buf: [256]u8 = undefined;
            const old_name = try std.fmt.bufPrint(&buf, "{}.{}", .{
                self.config.file_path,
                i,
            });
            const new_name = try std.fmt.bufPrint(&buf, "{}.{}", .{
                self.config.file_path,
                i + 1,
            });

            _ = std.fs.cwd().renameZ(old_name, new_name) catch {};
        }

        // Rename current to .1
        var buf: [256]u8 = undefined;
        const archived_name = try std.fmt.bufPrint(&buf, "{}.1", .{
            self.config.file_path,
        });
        _ = std.fs.cwd().renameZ(self.config.file_path, archived_name) catch {};

        // Open new file
        try self.openFile();
    }

    pub fn deinit(self: *AuditLogger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |f| {
            f.close();
        }
        self.allocator.free(self.config.file_path);
    }

    pub fn setRetentionPolicy(self: *AuditLogger, policy: RetentionPolicy) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.retention = policy;
    }

    pub fn enforceRetentionPolicy(self: *AuditLogger) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const retention_seconds = self.retention.retention_days * 86400;
        const cutoff_time = now - retention_seconds;

        // Find files to delete
        var i: i32 = @intCast(self.config.max_files);
        while (i > 0) : (i -= 1) {
            var buf: [256]u8 = undefined;
            const archived_name = try std.fmt.bufPrint(&buf, "{}.{}", .{
                self.config.file_path,
                i,
            });

            if (std.fs.cwd().statZ(archived_name)) |stat| {
                if (stat.mtime < cutoff_time) {
                    if (self.retention.secure_delete) {
                        try self.secureDelete(archived_name);
                    } else {
                        _ = std.fs.cwd().deleteFileZ(archived_name) catch {};
                    }
                }
            } else |_| {}
        }
    }

    fn secureDelete(self: *AuditLogger, file_path: []const u8) !void {
        _ = self;
        // Overwrite with zeros (DoD 5220.22-M single-pass)
        if (std.fs.cwd().openFileZ(file_path, .{
            .mode = .read_write,
        })) |file| {
            const size = try file.getEndPos();
            var zeros: [4096]u8 = undefined;
            @memset(&zeros, 0);

            var offset: u64 = 0;
            while (offset < size) {
                const to_write = @min(4096, size - offset);
                try file.pwriteAll(&zeros[0..to_write], offset);
                offset += to_write;
            }
            file.close();

            _ = std.fs.cwd().deleteFileZ(file_path) catch {};
        } else |_| {}
    }

    pub fn getStatistics(self: *AuditLogger) AuditStatistics {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .total_events = self.event_count,
            .current_file_size = self.current_size,
            .max_file_size = self.config.max_file_size,
        };
    }
};

pub const AuditStatistics = struct {
    total_events: u64,
    current_file_size: u64,
    max_file_size: u64,
};

// Tests
const testing = std.testing;

test "audit_log: create and log event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit.log",
        .max_file_size = 1024,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const event = AuditEvent{
        .timestamp = 1234567890,
        .event_type = .session_created,
        .session_id = "sess_001",
        .user = "testuser",
        .host = "mainframe1",
        .action = "connect",
        .details = null,
        .status = .success,
        .err = null,
    };

    try logger.logEvent(event);

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 1);
}

test "audit_log: multiple events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_multi.log",
        .max_file_size = 10_000,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    for (0..5) |i| {
        var buf: [32]u8 = undefined;
        const session_id = try std.fmt.bufPrint(&buf, "sess_{:03}", .{i});

        const event = AuditEvent{
            .timestamp = 1234567890 + @as(i64, @intCast(i)),
            .event_type = .session_created,
            .session_id = session_id,
            .user = "testuser",
            .host = "mainframe1",
            .action = "connect",
            .details = null,
            .status = .success,
            .err = null,
        };

        try logger.logEvent(event);
    }

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 5);
}

test "audit_log: event types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_types.log",
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const event_types = [_]EventType{
        .session_created,
        .session_connected,
        .authentication,
        .data_access,
        .session_closed,
    };

    for (event_types) |et| {
        const event = AuditEvent{
            .timestamp = 1234567890,
            .event_type = et,
            .session_id = "sess_001",
            .user = "testuser",
            .host = "mainframe1",
            .action = "test",
            .details = null,
            .status = .success,
            .err = null,
        };

        try logger.logEvent(event);
    }

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 5);
}

test "audit_log: event status values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_status.log",
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const statuses = [_]EventStatus{
        .success,
        .failed,
        .partial,
        .denied,
    };

    for (statuses) |status| {
        const event = AuditEvent{
            .timestamp = 1234567890,
            .event_type = .authentication,
            .session_id = "sess_001",
            .user = "testuser",
            .host = "mainframe1",
            .action = "authenticate",
            .details = null,
            .status = status,
            .err = if (status == .failed) "invalid_password" else null,
        };

        try logger.logEvent(event);
    }

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 4);
}

test "audit_log: with error details" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_error.log",
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const event = AuditEvent{
        .timestamp = 1234567890,
        .event_type = .connection_error,
        .session_id = "sess_001",
        .user = "testuser",
        .host = "mainframe1",
        .action = "connect",
        .details = "Connection timeout after 30s",
        .status = .failed,
        .err = "TIMEOUT",
    };

    try logger.logEvent(event);

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 1);
}

test "audit_log: disabled logging" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_disabled.log",
        .log_level = .disabled,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const event = AuditEvent{
        .timestamp = 1234567890,
        .event_type = .session_created,
        .session_id = "sess_001",
        .user = "testuser",
        .host = "mainframe1",
        .action = "connect",
        .details = null,
        .status = .success,
        .err = null,
    };

    try logger.logEvent(event);

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 0);
}

test "audit_log: statistics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_stats.log",
        .max_file_size = 5_000_000,
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    for (0..3) |i| {
        var buf: [32]u8 = undefined;
        const session_id = try std.fmt.bufPrint(&buf, "sess_{:03}", .{i});

        const event = AuditEvent{
            .timestamp = 1234567890 + @as(i64, @intCast(i)),
            .event_type = .session_created,
            .session_id = session_id,
            .user = "testuser",
            .host = "mainframe1",
            .action = "connect",
            .details = null,
            .status = .success,
            .err = null,
        };

        try logger.logEvent(event);
    }

    const stats = logger.getStatistics();
    try testing.expect(stats.total_events == 3);
    try testing.expect(stats.max_file_size == 5_000_000);
}

test "audit_log: retention policy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_retention.log",
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const policy = RetentionPolicy{
        .retention_days = 30,
        .archive_days = 7,
        .enable_compression = true,
        .secure_delete = true,
    };

    logger.setRetentionPolicy(policy);
    try testing.expect(logger.retention.retention_days == 30);
}

test "audit_log: enforce retention" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuditConfig{
        .file_path = "/tmp/test_audit_enforce.log",
    };

    var logger = try AuditLogger.init(allocator, config);
    defer logger.deinit();

    const policy = RetentionPolicy{
        .retention_days = 30,
        .secure_delete = false,
    };

    logger.setRetentionPolicy(policy);

    // Log an event
    const event = AuditEvent{
        .timestamp = 1234567890,
        .event_type = .session_created,
        .session_id = "sess_001",
        .user = "testuser",
        .host = "mainframe1",
        .action = "connect",
        .details = null,
        .status = .success,
        .err = null,
    };

    try logger.logEvent(event);

    // Enforce retention (should not crash)
    try logger.enforceRetentionPolicy();

    try testing.expect(logger.retention.retention_days == 30);
}
