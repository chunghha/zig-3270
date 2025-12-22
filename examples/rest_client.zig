// REST API Client Example
// Demonstrates how to use the zig-3270 REST API programmatically
//
// This example provides a simple HTTP client library for interacting with the
// zig-3270 REST API endpoints, including session management, screen capture,
// and administrative operations.

const std = @import("std");
const json = std.json;

/// HTTP client configuration
pub const HttpConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 3270,
    base_path: []const u8 = "/api/v1",
    timeout_ms: u64 = 5000,
    auth: ?Auth = null,

    pub const Auth = union(enum) {
        bearer: []const u8,
        basic: struct {
            username: []const u8,
            password: []const u8,
        },
    };
};

/// Response wrapper for API responses
pub const ApiResponse = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ApiResponse) void {
        var it = self.headers.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }

    pub fn parseJson(self: *const ApiResponse, comptime T: type) !T {
        return try json.parseFromSlice(T, self.allocator, self.body, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Session creation request
pub const SessionRequest = struct {
    host: []const u8,
    port: u16,
    application: ?[]const u8 = null,
    user: ?[]const u8 = null,
};

/// Session response
pub const SessionResponse = struct {
    session_id: []const u8,
    host: []const u8,
    port: u16,
    state: []const u8,
    created_at: i64,
    last_activity: i64,
};

/// Screen response
pub const ScreenResponse = struct {
    session_id: []const u8,
    screen_data: []const u8,
    cursor_row: u32,
    cursor_col: u32,
    width: u32 = 80,
    height: u32 = 24,
};

/// Input request
pub const InputRequest = struct {
    data: []const u8,
    append: bool = false,
};

/// Audit log entry
pub const AuditLogEntry = struct {
    timestamp: i64,
    event_type: []const u8,
    session_id: ?[]const u8,
    user: ?[]const u8,
    action: []const u8,
    status: []const u8,
};

/// REST API Client
pub const RestClient = struct {
    config: HttpConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: HttpConfig) RestClient {
        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    /// Execute HTTP request and return response (simplified version)
    fn httpRequest(
        self: *const RestClient,
        _method: []const u8,
        path: []const u8,
        _body: ?[]const u8,
    ) !ApiResponse {
        _ = _method;
        _ = _body;

        const full_url = try std.fmt.allocPrint(
            self.allocator,
            "http://{s}:{d}{s}{s}",
            .{ self.config.host, self.config.port, self.config.base_path, path },
        );
        defer self.allocator.free(full_url);

        var response_body = std.ArrayList(u8).init(self.allocator);

        // Simplified: return empty response for demonstration
        // Real implementation would use std.http.Client
        return ApiResponse{
            .status = 200,
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .body = try response_body.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    // Session Management Endpoints

    /// Create a new session
    pub fn createSession(
        self: *const RestClient,
        req: SessionRequest,
    ) !SessionResponse {
        const req_body = try json.stringifyAlloc(
            self.allocator,
            req,
            .{},
        );
        defer self.allocator.free(req_body);

        var response = try self.httpRequest("POST", "/sessions", req_body);
        defer response.deinit();

        if (response.status != 200) {
            std.debug.print("Error creating session: {d}\n", .{response.status});
            return error.SessionCreationFailed;
        }

        return try response.parseJson(SessionResponse);
    }

    /// List all sessions
    pub fn listSessions(self: *const RestClient) ![]SessionResponse {
        var response = try self.httpRequest("GET", "/sessions", null);
        defer response.deinit();

        if (response.status != 200) {
            return error.SessionListFailed;
        }

        // Parse array response
        var parser = json.Parser.init(self.allocator, false);
        defer parser.deinit();

        const parsed = try parser.parse(response.body);
        defer parsed.deinit();

        // Simplified: return empty slice for now
        return &[_]SessionResponse{};
    }

    /// Get session details
    pub fn getSession(
        self: *const RestClient,
        session_id: []const u8,
    ) !SessionResponse {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}",
            .{session_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("GET", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.SessionNotFound;
        }

        return try response.parseJson(SessionResponse);
    }

    /// Close a session
    pub fn closeSession(
        self: *const RestClient,
        session_id: []const u8,
    ) !void {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}",
            .{session_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("DELETE", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.SessionCloseFailed;
        }
    }

    // Screen Capture Endpoints

    /// Get current screen
    pub fn getScreen(
        self: *const RestClient,
        session_id: []const u8,
    ) !ScreenResponse {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}/screen",
            .{session_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("GET", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.ScreenCaptureFailed;
        }

        return try response.parseJson(ScreenResponse);
    }

    // Input Endpoints

    /// Send input to session
    pub fn sendInput(
        self: *const RestClient,
        session_id: []const u8,
        input: InputRequest,
    ) !void {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}/input",
            .{session_id},
        );
        defer self.allocator.free(path);

        const req_body = try json.stringifyAlloc(
            self.allocator,
            input,
            .{},
        );
        defer self.allocator.free(req_body);

        var response = try self.httpRequest("POST", path, req_body);
        defer response.deinit();

        if (response.status != 200) {
            return error.InputSendFailed;
        }
    }

    // Session Control Endpoints

    /// Suspend a session
    pub fn suspendSession(
        self: *const RestClient,
        session_id: []const u8,
    ) !void {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}/suspend",
            .{session_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("POST", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.SuspendFailed;
        }
    }

    /// Resume a suspended session
    pub fn resumeSession(
        self: *const RestClient,
        session_id: []const u8,
    ) !void {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}/resume",
            .{session_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("POST", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.ResumeFailed;
        }
    }

    /// Migrate session to different endpoint
    pub fn migrateSession(
        self: *const RestClient,
        session_id: []const u8,
        target_host: []const u8,
        target_port: u16,
    ) !void {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/sessions/{s}/migrate",
            .{session_id},
        );
        defer self.allocator.free(path);

        const migration_req = .{
            .target_host = target_host,
            .target_port = target_port,
        };

        const req_body = try json.stringifyAlloc(
            self.allocator,
            migration_req,
            .{},
        );
        defer self.allocator.free(req_body);

        var response = try self.httpRequest("PUT", path, req_body);
        defer response.deinit();

        if (response.status != 200) {
            return error.MigrationFailed;
        }
    }

    // Endpoint Management

    /// Get endpoint health status
    pub fn getEndpointHealth(
        self: *const RestClient,
        endpoint_id: []const u8,
    ) !std.json.Value {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/endpoints/{s}/health",
            .{endpoint_id},
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("GET", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.HealthCheckFailed;
        }

        var parser = json.Parser.init(self.allocator, false);
        defer parser.deinit();

        const parsed = try parser.parse(response.body);
        return parsed.value;
    }

    // Audit & Compliance

    /// Query audit logs
    pub fn queryAuditLogs(
        self: *const RestClient,
        limit: u32,
        offset: u32,
    ) ![]AuditLogEntry {
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/audit?limit={d}&offset={d}",
            .{ limit, offset },
        );
        defer self.allocator.free(path);

        var response = try self.httpRequest("GET", path, null);
        defer response.deinit();

        if (response.status != 200) {
            return error.AuditQueryFailed;
        }

        // Simplified: return empty slice
        return &[_]AuditLogEntry{};
    }

    /// Get compliance report
    pub fn getComplianceReport(self: *const RestClient) !std.json.Value {
        var response = try self.httpRequest("GET", "/compliance/report", null);
        defer response.deinit();

        if (response.status != 200) {
            return error.ComplianceReportFailed;
        }

        var parser = json.Parser.init(self.allocator, false);
        defer parser.deinit();

        const parsed = try parser.parse(response.body);
        return parsed.value;
    }
};

// Example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client with default config
    const config = HttpConfig{
        .host = "localhost",
        .port = 3270,
    };

    _ = RestClient.init(allocator, config);

    std.debug.print("zig-3270 REST API Client Example\n\n", .{});

    // Example 1: Create session
    std.debug.print("1. Creating session...\n", .{});
    _ = SessionRequest{
        .host = "mainframe.example.com",
        .port = 23,
        .user = "testuser",
    };

    // In a real scenario, the API server would be running
    // Commented out to avoid connection failures in examples
    // const session = client.createSession(session_req) catch |err| {
    //     std.debug.print("Note: API server not running. Error: {}\n", .{err});
    //     return;
    // };
    // std.debug.print("   Created session: {s}\n", .{session.session_id});

    // Example 2: Send input to session
    // const input = InputRequest{
    //     .data = "mypassword\n",
    //     .append = false,
    // };
    // try client.sendInput(session.session_id, input);
    // std.debug.print("2. Sent input to session\n", .{});

    // Example 3: Capture screen
    // const screen = try client.getScreen(session.session_id);
    // std.debug.print("3. Captured screen: {d}x{d}\n", .{screen.width, screen.height});

    // Example 4: Suspend session
    // try client.suspendSession(session.session_id);
    // std.debug.print("4. Suspended session\n", .{});

    // Example 5: Resume session
    // try client.resumeSession(session.session_id);
    // std.debug.print("5. Resumed session\n", .{});

    // Example 6: Query audit logs
    // const logs = try client.queryAuditLogs(100, 0);
    // std.debug.print("6. Retrieved {d} audit logs\n", .{logs.len});

    // Example 7: Get compliance report
    // const report = try client.getComplianceReport();
    // std.debug.print("7. Generated compliance report\n", .{});

    // Example 8: Close session
    // try client.closeSession(session.session_id);
    // std.debug.print("8. Closed session\n", .{});

    std.debug.print("\nExample: REST API Client Library\n", .{});
    std.debug.print("Features:\n", .{});
    std.debug.print("  - Session management (create, list, get, close)\n", .{});
    std.debug.print("  - Screen capture\n", .{});
    std.debug.print("  - Input injection\n", .{});
    std.debug.print("  - Session control (suspend, resume, migrate)\n", .{});
    std.debug.print("  - Endpoint health checks\n", .{});
    std.debug.print("  - Audit log queries\n", .{});
    std.debug.print("  - Compliance reporting\n", .{});
    std.debug.print("  - Authentication support (bearer token, basic auth)\n", .{});
    std.debug.print("\nNote: Requires REST API server running on localhost:3270\n", .{});
}

// Tests
test "rest_client_types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = HttpConfig{
        .host = "localhost",
        .port = 3270,
    };

    const client = RestClient.init(allocator, config);

    try std.testing.expect(std.mem.eql(u8, client.config.host, "localhost"));
    try std.testing.expect(client.config.port == 3270);
    try std.testing.expect(std.mem.eql(u8, client.config.base_path, "/api/v1"));
}

test "rest_client_auth_bearer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = HttpConfig{
        .host = "localhost",
        .port = 3270,
        .auth = HttpConfig.Auth{
            .bearer = "test-token",
        },
    };

    const client = RestClient.init(allocator, config);

    try std.testing.expect(client.config.auth != null);
    if (client.config.auth) |auth| {
        switch (auth) {
            .bearer => |token| {
                try std.testing.expect(std.mem.eql(u8, token, "test-token"));
            },
            else => unreachable,
        }
    }
}

test "rest_client_auth_basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = HttpConfig{
        .host = "localhost",
        .port = 3270,
        .auth = HttpConfig.Auth{
            .basic = .{
                .username = "user",
                .password = "pass",
            },
        },
    };

    const client = RestClient.init(allocator, config);

    try std.testing.expect(client.config.auth != null);
    if (client.config.auth) |auth| {
        switch (auth) {
            .basic => |creds| {
                try std.testing.expect(std.mem.eql(u8, creds.username, "user"));
                try std.testing.expect(std.mem.eql(u8, creds.password, "pass"));
            },
            else => unreachable,
        }
    }
}
