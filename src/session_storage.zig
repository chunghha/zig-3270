const std = @import("std");
const screen = @import("screen.zig");
const protocol = @import("protocol.zig");

/// Session state storage and recovery
pub const SessionStorage = struct {
    pub const SessionState = struct {
        screen_buffer: []u8,
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        keyboard_locked: bool,
        timestamp: i64,
        checksum: u32,

        pub fn deinit(self: SessionState, allocator: std.mem.Allocator) void {
            allocator.free(self.screen_buffer);
        }
    };

    allocator: std.mem.Allocator,
    session_dir: []u8,

    /// Initialize session storage with session directory
    pub fn init(allocator: std.mem.Allocator, session_dir: []const u8) !SessionStorage {
        // Create session directory if it doesn't exist
        std.fs.cwd().makeDir(session_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        return .{
            .allocator = allocator,
            .session_dir = try allocator.dupe(u8, session_dir),
        };
    }

    /// Save session state to disk
    pub fn save_session(
        self: SessionStorage,
        scr: *const screen.Screen,
        cursor_row: u16,
        cursor_col: u16,
        keyboard_locked: bool,
    ) !void {
        const session_file = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.session_dir, "session.bin" },
        );
        defer self.allocator.free(session_file);

        const file = try std.fs.cwd().createFile(session_file, .{});
        defer file.close();

        // Calculate checksum
        const checksum = calculate_checksum(scr.buffer);

        // Write header
        const timestamp = std.time.milliTimestamp();
        try file.writeAll(std.mem.asBytes(&scr.rows));
        try file.writeAll(std.mem.asBytes(&scr.cols));
        try file.writeAll(std.mem.asBytes(&cursor_row));
        try file.writeAll(std.mem.asBytes(&cursor_col));
        try file.writeAll(std.mem.asBytes(&keyboard_locked));
        try file.writeAll(std.mem.asBytes(&timestamp));
        try file.writeAll(std.mem.asBytes(&checksum));

        // Write screen buffer
        try file.writeAll(scr.buffer);
    }

    /// Load session state from disk
    pub fn load_session(self: SessionStorage) !?SessionState {
        const session_file = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.session_dir, "session.bin" },
        );
        defer self.allocator.free(session_file);

        const file = std.fs.cwd().openFile(session_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return null;
            }
            return err;
        };
        defer file.close();

        // Read header
        var rows: u16 = 0;
        var cols: u16 = 0;
        var cursor_row: u16 = 0;
        var cursor_col: u16 = 0;
        var keyboard_locked: bool = false;
        var timestamp: i64 = 0;
        var checksum: u32 = 0;

        var header_buf: [32]u8 = undefined;
        const bytes_read = try file.read(&header_buf);

        if (bytes_read < 25) {
            return error.InvalidSessionFile;
        }

        var idx: usize = 0;
        rows = std.mem.bytesAsValue(u16, header_buf[idx .. idx + 2]).*;
        idx += 2;
        cols = std.mem.bytesAsValue(u16, header_buf[idx .. idx + 2]).*;
        idx += 2;
        cursor_row = std.mem.bytesAsValue(u16, header_buf[idx .. idx + 2]).*;
        idx += 2;
        cursor_col = std.mem.bytesAsValue(u16, header_buf[idx .. idx + 2]).*;
        idx += 2;
        keyboard_locked = header_buf[idx] != 0;
        idx += 1;
        timestamp = std.mem.bytesAsValue(i64, header_buf[idx .. idx + 8]).*;
        idx += 8;
        checksum = std.mem.bytesAsValue(u32, header_buf[idx .. idx + 4]).*;

        // Read screen buffer
        const buffer_size = rows * cols;
        const screen_buffer = try self.allocator.alloc(u8, buffer_size);

        const actual_read = try file.read(screen_buffer);
        if (actual_read != buffer_size) {
            self.allocator.free(screen_buffer);
            return error.InvalidSessionFile;
        }

        // Verify checksum
        const calculated_checksum = calculate_checksum(screen_buffer);
        if (calculated_checksum != checksum) {
            self.allocator.free(screen_buffer);
            return error.ChecksumMismatch;
        }

        return SessionState{
            .screen_buffer = screen_buffer,
            .rows = rows,
            .cols = cols,
            .cursor_row = cursor_row,
            .cursor_col = cursor_col,
            .keyboard_locked = keyboard_locked,
            .timestamp = timestamp,
            .checksum = checksum,
        };
    }

    /// Delete session file
    pub fn delete_session(self: SessionStorage) !void {
        const session_file = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.session_dir, "session.bin" },
        );
        defer self.allocator.free(session_file);

        std.fs.cwd().deleteFile(session_file) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };
    }

    /// Deinitialize session storage
    pub fn deinit(self: SessionStorage) void {
        self.allocator.free(self.session_dir);
    }
};

/// Calculate simple checksum for session buffer
fn calculate_checksum(buffer: []const u8) u32 {
    var sum: u32 = 0;

    for (buffer) |byte| {
        sum +%= @as(u32, byte) * 31;
    }

    return sum;
}

// Tests
test "session_storage: init creates session directory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_dir = "/tmp/zig3270_test_session";
    std.fs.cwd().deleteTree(test_dir) catch {};

    const storage = try SessionStorage.init(allocator, test_dir);
    defer storage.deinit();

    // Directory should exist
    var dir = try std.fs.cwd().openDir(test_dir, .{});
    defer dir.close();

    std.fs.cwd().deleteTree(test_dir) catch {};
}

test "session_storage: save and load session" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_dir = "/tmp/zig3270_test_session";
    std.fs.cwd().deleteTree(test_dir) catch {};

    const storage = try SessionStorage.init(allocator, test_dir);
    defer storage.deinit();

    // Create a screen
    var scr = try screen.Screen.init(allocator, 24, 80);
    defer scr.deinit();

    try scr.write_char(0, 0, 'A');
    try scr.write_char(0, 1, 'B');

    // Save session
    try storage.save_session(&scr, 5, 10, true);

    // Load session
    const loaded = try storage.load_session();
    defer if (loaded) |state| state.deinit(allocator);

    try std.testing.expect(loaded != null);
    const state = loaded.?;
    try std.testing.expectEqual(@as(u16, 24), state.rows);
    try std.testing.expectEqual(@as(u16, 80), state.cols);
    try std.testing.expectEqual(@as(u16, 5), state.cursor_row);
    try std.testing.expectEqual(@as(u16, 10), state.cursor_col);
    try std.testing.expect(state.keyboard_locked);

    std.fs.cwd().deleteTree(test_dir) catch {};
}

test "session_storage: checksum verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_dir = "/tmp/zig3270_test_session_checksum";
    std.fs.cwd().deleteTree(test_dir) catch {};

    const storage = try SessionStorage.init(allocator, test_dir);
    defer storage.deinit();

    var scr = try screen.Screen.init(allocator, 10, 10);
    defer scr.deinit();

    try storage.save_session(&scr, 0, 0, false);

    const loaded = try storage.load_session();
    try std.testing.expect(loaded != null);
    if (loaded) |state| {
        state.deinit(allocator);
    }

    std.fs.cwd().deleteTree(test_dir) catch {};
}

test "session_storage: load_session returns null when file missing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_dir = "/tmp/zig3270_test_session_missing";
    std.fs.cwd().deleteTree(test_dir) catch {};

    const storage = try SessionStorage.init(allocator, test_dir);
    defer storage.deinit();

    const loaded = try storage.load_session();
    try std.testing.expectEqual(@as(?SessionStorage.SessionState, null), loaded);

    std.fs.cwd().deleteTree(test_dir) catch {};
}

test "session_storage: delete_session removes file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_dir = "/tmp/zig3270_test_session_delete";
    std.fs.cwd().deleteTree(test_dir) catch {};

    const storage = try SessionStorage.init(allocator, test_dir);
    defer storage.deinit();

    var scr = try screen.Screen.init(allocator, 10, 10);
    defer scr.deinit();

    try storage.save_session(&scr, 0, 0, false);
    try storage.delete_session();

    const loaded = try storage.load_session();
    try std.testing.expectEqual(@as(?SessionStorage.SessionState, null), loaded);

    std.fs.cwd().deleteTree(test_dir) catch {};
}
