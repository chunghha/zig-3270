const std = @import("std");

pub const ConnectionProfile = struct {
    name: []const u8,
    host: []const u8,
    port: u16,
    timeout: u32 = 5000,
    auto_reconnect: bool = true,
    max_retries: u32 = 3,
};

pub const ProfileManager = struct {
    allocator: std.mem.Allocator,
    profiles: std.StringHashMap(ConnectionProfile),

    pub fn init(allocator: std.mem.Allocator) ProfileManager {
        return .{
            .allocator = allocator,
            .profiles = std.StringHashMap(ConnectionProfile).init(allocator),
        };
    }

    pub fn deinit(self: *ProfileManager) void {
        self.profiles.deinit();
    }

    /// Add a new profile
    pub fn add_profile(self: *ProfileManager, profile: ConnectionProfile) !void {
        try self.profiles.put(profile.name, profile);
    }

    /// Get a profile by name
    pub fn get_profile(self: ProfileManager, name: []const u8) ?ConnectionProfile {
        return self.profiles.get(name);
    }

    /// List all profile names
    pub fn list_profiles(self: ProfileManager, allocator: std.mem.Allocator) ![][]const u8 {
        const count = self.profiles.count();
        var names = try allocator.alloc([]const u8, count);

        var i: usize = 0;
        var iter = self.profiles.keyIterator();
        while (iter.next()) |key| {
            names[i] = key.*;
            i += 1;
        }

        return names;
    }

    /// Remove a profile
    pub fn remove_profile(self: *ProfileManager, name: []const u8) bool {
        return self.profiles.remove(name);
    }
};

// Tests
test "create connection profile" {
    const profile = ConnectionProfile{
        .name = "test",
        .host = "localhost",
        .port = 23,
    };

    try std.testing.expectEqualSlices(u8, "test", profile.name);
    try std.testing.expectEqualSlices(u8, "localhost", profile.host);
    try std.testing.expectEqual(@as(u16, 23), profile.port);
    try std.testing.expectEqual(@as(u32, 5000), profile.timeout);
}

test "profile manager init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pm = ProfileManager.init(allocator);
    defer pm.deinit();

    try std.testing.expectEqual(@as(usize, 0), pm.profiles.count());
}

test "add and retrieve profile" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pm = ProfileManager.init(allocator);
    defer pm.deinit();

    const profile = ConnectionProfile{
        .name = "mvs",
        .host = "mvs38j.com",
        .port = 23,
        .timeout = 10000,
    };

    try pm.add_profile(profile);

    const retrieved = pm.get_profile("mvs");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqualSlices(u8, "mvs38j.com", retrieved.?.host);
    try std.testing.expectEqual(@as(u16, 23), retrieved.?.port);
    try std.testing.expectEqual(@as(u32, 10000), retrieved.?.timeout);
}

test "list profiles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pm = ProfileManager.init(allocator);
    defer pm.deinit();

    try pm.add_profile(.{
        .name = "mvs",
        .host = "mvs38j.com",
        .port = 23,
    });
    try pm.add_profile(.{
        .name = "tso",
        .host = "tso.example.com",
        .port = 23,
    });

    const names = try pm.list_profiles(allocator);
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);
}

test "remove profile" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pm = ProfileManager.init(allocator);
    defer pm.deinit();

    try pm.add_profile(.{
        .name = "mvs",
        .host = "mvs38j.com",
        .port = 23,
    });

    const removed = pm.remove_profile("mvs");
    try std.testing.expect(removed);

    const retrieved = pm.get_profile("mvs");
    try std.testing.expect(retrieved == null);
}
